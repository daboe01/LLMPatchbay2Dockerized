# backend for PatchbayLabs
# 29.10.24 by daniel boehringer
# Copyright 2024, All rights reserved.
#

use Mojolicious::Lite;
use Mojo::Pg;
use Data::Dumper;
use Mojo::File;
use Mojo::JSON qw(decode_json encode_json);
use Encode; # utf8 and friends
use Mojo::Template;
use Text::CSV;
use Statistics::R;
use MIME::Base64;
use XML::XML2JSON;
use Archive::Zip;
use File::Basename;
use IPC::Open3;

no warnings 'uninitialized';

$ENV{MOJO_MAX_MESSAGE_SIZE} = 3_073_741_824;

helper pg => sub { state $pg = Mojo::Pg->new('postgresql://docker:docker@localhost/llm_patchbay') };

#
# begin minion setup
#

# create minion db as needed
eval {
    app->pg->db->query("CREATE DATABASE minion");
};

plugin Minion => {Pg => 'postgresql://docker:docker@localhost/minion'};

#
# end minion setup
#

my $prefix = $ENV{NB_PREFIX} || '';
my $inference_proto = $ENV{NB_PREFIX} ? 'http' : 'https';

# Check for the NB_PREFIX environment variable and set it as the URL prefix.
if ($prefix ne '')
{
    $prefix = "/$prefix" unless $prefix =~ m{^/};
    app->static->prefix($prefix);
    app->log->info("Serving from the prefix '$prefix'");
}

app->minion->add_task(process_single_input => sub {
    my ($job, $idinput) = @_;
    my $app = $job->app;

    my $input = $app->pg->db->query(q{select * from input_data where id = ?}, $idinput)->hash;

    unless ($input) {
        $app->log->error("Input data with id $idinput not found for job $job->id. Failing.");
        return $job->fail("Input data with id $idinput not found.");
    }

    eval {
        my $block = $app->pg->db->query('select blocks.id, type from blocks join blocks_catalogue on idblock =  blocks_catalogue.id where idproject = ? and outputs is null and type != 8', $input->{idprompt})->hash;
        my $result = $app->get_result_of_block_id($block->{id}, $input->{content});

        # Insert the result into the output table.
        $app->pg->db->insert('output_data', {content => $result, idinput => $idinput, idprompt => $input->{idprompt}});

        $job->finish;
    };

    if (my $error = $@) {
        my $error_string = "$error";
        warn $error_string;
        $job->fail($error_string);
    }
});

# turn browser cache off
hook after_dispatch => sub {
    my $tx = shift;
    my $e = Mojo::Date->new(time-100);
    $tx->res->headers->header(Expires => $e);
    $tx->res->headers->header('X-ARGOS-Routing' => '8888');
};

# Set up routing - either with or without prefix
my $r = $prefix ? app->routes->under($prefix) : app->routes;

# Redirect root to Frontend
$r->get('/' => sub {
    my $self = shift;
    my $redirect_url = $prefix ? "$prefix/Frontend/index.html" : "/Frontend/index.html";
    $self->redirect_to($redirect_url);
});

$r->post('/LLM/upload' => sub {
    my $self = shift;
    my $upload_dir = '/upload';

    my $uploads = $self->req->uploads('files[]');

    # Ensure the upload directory exists
    my $dir_path = Mojo::File->new($upload_dir);
    eval { $dir_path->make_path unless -d $dir_path; };

    if ($@) {
        $self->app->log->error(
        "Failed to create upload directory '$upload_dir': $@");
        return $self->render(
                                status => 500,
                                json   => {
                                                error =>
                                                "Server configuration error: Could not create upload directory."
                                            }
                             );
    }

    my @results;

    for my $upload (@$uploads) {
        my $filename     = $upload->filename;
        my $content_type = $upload->headers->content_type;

        if ( $filename =~ /\.zip$/i ) {

            # Create a temporary file to reliably store the upload
            my $temp_zip_file = Mojo::File::tempfile();
            my $temp_zip_path = $temp_zip_file->to_string;

            # Move the uploaded content to our temp file
            $upload->move_to($temp_zip_path);

            my $zip = Archive::Zip->new();

            if ( $zip->read($temp_zip_path) != Archive::Zip::AZ_OK ) {
                unlink $temp_zip_path; # Clean up temp file on failure
                return $self->render(
                                        status => 500,
                                        json =>
                                        { error => "Server error: Failed to read the ZIP file '$filename'." }
                                     );
            }

            # Iterate through each member (file/dir) in the zip archive
            for my $member ( $zip->members() ) {

                # Skip directories and macOS-specific resource files
                next if $member->isDirectory() || $member->fileName() =~ m{^__MACOSX/};

                # Get only the base filename, stripping internal zip paths
                my $file_basename = basename( $member->fileName() );

                # Construct the final destination path in the root of the upload dir
                my $destination_path = Mojo::File->new( $upload_dir, $file_basename );

                # Extract the file to the destination
                if ( $member->extractToFileNamed( $destination_path->to_string ) != Archive::Zip::AZ_OK )
                {
                    unlink $temp_zip_path; # Clean up temp file on failure
                    return $self->render(
                                            status => 500,
                                            json   => {
                                                            error =>
                                                            "Server error: Failed to extract a file from '$filename'."
                                                       }
                                        );
                }
            }

            # Clean up the temporary zip file after successful extraction
            unlink $temp_zip_path;
            push @results, { file => $filename, status => 'unpacked' };

        }
        else {
            my $destination_path = Mojo::File->new( $upload_dir, $filename );
            $upload->move_to( $destination_path->to_string );
            push @results, { file => $filename, status => 'saved' };
        }
    }

    $self->render(
                    status  => 200,
                    json    => {
                                message => "Upload process completed.",
                                files_processed => \@results
                               }
                );
});

# In backend.pl, add this to your routing section ($r->...)

$r->get('/LLM/download_csv' => sub {
    my $self = shift;

    my $results = $self->pg->db->query(q{
                                            SELECT
                                                i.id AS input_id,
                                                i.title AS input_title,
                                                o.id AS output_id,
                                                o.content AS output_content
                                            FROM
                                                output_data o
                                            JOIN
                                                input_data i ON o.idinput = i.id
                                            ORDER BY
                                                i.id
                                        })->hashes;

    # Handle case where there's no data to export.
    unless (@$results) {
        return $self->render(status => 404, text => "No output data found.");
    }

    # 3. Generate the CSV content in memory.
    my $csv_string = '';
    # Open a "filehandle" to our string variable.
    open my $fh, '>', \$csv_string or die "Cannot open memory filehandle: $!";

    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1});

    # Get headers from the first result row and write them to the CSV.
    my @headers = keys %{ $results->[0] };
    $csv->say($fh, \@headers);

    # Write each data row to the CSV.
    for my $row (@$results) {
        # A hash slice ensures the values are in the correct order.
        $csv->say($fh, [ @{$row}{@headers} ]);
    }

    close $fh; # Close the memory handle.

    $self->res->headers->content_type('text/csv; charset=utf-8');
    $self->res->headers->content_disposition("attachment; filename=\"patchbay_outputs.csv\"");

    # 5. Render the CSV string as the response body.
    $self->render(text => $csv_string);
});

$r->delete('/LLM/delete_all_inputs' => sub
{
    my $self = shift;

    $self->pg->db->query( 'DELETE FROM input_data' );

    $self->render(json =>   {
                                message => "Deleted all inputs."
                            });
});

$r->post('/LLM/import_from_upload/:id' => [id => qr/\d+/] => sub {
    my $self = shift;
    my $idproject = $self->param('id');
    my $upload_dir = '/upload';

    my $dir = Mojo::File->new($upload_dir);
    my @files = $dir->list->each;

    my $i = 0;

    foreach my $file (@files) {
         my $content = Encode::decode 'UTF-8', $file->slurp;
         my $filename = $file->basename;

         $self->pg->db->insert('input_data', {
                                               title => $filename,
                                               content => $content,
                                               idprompt => $idproject
                                             });
         $i++;
         $file->remove;
    }

    $self->render(text => 'OK '.$i);
});

$r->get('/LLM/get_data_from_dataset/:dataset_name' => sub
{
    my $self          = shift;
    my $dataset_name  = $self->param('dataset_name');
    my $datapoints    = $self->pg->db->query(  q{
        select embedded_data.*
        from embedded_datasets
        join embedded_data on embedded_datasets.id = idembedded_datasets
        where embedded_datasets.name = ?
    }, $dataset_name)->hashes;
    $self->render(json => $datapoints);
});

$r->get('/LLM/get_payload_for_label_from_dataset/:label/:dataset_name' => sub
{
    my $self          = shift;
    my $dataset_name  = $self->param('dataset_name');
    my $label         = $self->param('label');
    my $datapoint     = $self->pg->db->query(  q{
        select embedded_data.*
        from embedded_datasets
        join embedded_data on embedded_datasets.id = idembedded_datasets
        where embedded_datasets.name = ? and label ~* ?
    }, $dataset_name, $label)->hash;

    $self->render(json => $datapoint);
});

$r->post('/LLM/get_matches_from_dataset_named/:name' => sub
{
    my $self          = shift;
    my $input         = decode 'UTF-8', $self->req->body;
    my $dataset_name  = $self->param('name');
    my $top_k         = $self->param('top_k') || 1;
    my $dataset       = $self->pg->db->query(  q{
        select embedding_models.name, embedded_datasets.id as iddataset, template, storage_entity, embedding_endpoint from embedded_datasets
        join embedding_models on embedding_models.id = idembedding_model
        where embedded_datasets.name = ?
    }, $dataset_name)->hash;
    unless ($dataset)
    {
        $self->render(text => 'NOK');
        return;
    }

    my $query_embedding = $self->get_embedding($dataset->{embedding_endpoint}, $dataset->{name}, $input, $dataset->{template});
    my $storage_entity  = $dataset->{storage_entity}; # fixme: sanitize to prevent SQL injections

    unless ($storage_entity)
    {
        $self->render(text => 'NOK');
        return;
    }

    my $sql = qq{
        select payload, label, 1 - ($storage_entity.embedding <=> ?) AS similarity

        from $storage_entity
        join embedded_data on embedded_data.id = iddata
        WHERE idembedded_datasets = ?
        order by 3 desc limit ?
    };

    $self->render(json => $self->pg->db->query($sql, $query_embedding, $dataset->{iddataset}, $top_k)->hashes);
});

$r->post('/LLM/import_embedding_dataset/:pk' => [pk => qr/\d+/] => sub
{
    my $self         = shift;
    my $pk           = $self->param('pk');
    my $preserve     = $self->param('preserve');
    my $remove       = $self->param('remove');

    my $dataset = $self->pg->db->query(q{
        select embedding_models.name, storage_entity, embedding_endpoint, template from embedded_datasets
        join embedding_models on embedding_models.id = idembedding_model
        where embedded_datasets.id = ?
    }, $pk)->hash;

    $self->pg->db->delete('embedded_data', {idembedded_datasets => $pk}) unless $preserve || $remove;

    my $csv = Text::CSV->new ({ binary => 1, auto_diag => 1, sep=> ';' });
    open my $fh, "<:utf8", \$self->req->body;
    my $hrref = $csv->getline($fh);
    $csv->column_names($hrref);

    while (my $c = $csv->getline_hr($fh))
    {
        # warn Dumper $c;

        eval {
            if ($remove)
            {
                $self->pg->db->delete('embedded_data', {label => $c->{label}, payload => $c->{payload}, idembedded_datasets => $pk});
                next;
            }

            # dupe prevention
            if ($preserve)
            {
                my $count = $self->pg->db->query(q{
                    select count(*)
                    from embedded_data
                    where label = ? and payload = ? and idembedded_datasets = ?

                }, $c->{label}, $c->{payload}, $pk)->hash->{count};

                warn "skipping dupe" if $count;
                next if $count;
            }
            my $query_embedding = $self->get_embedding($dataset->{embedding_endpoint}, $dataset->{name}, $c->{payload}, $dataset->{template});

            my $iddata = $self->pg->db->insert('embedded_data', {label => $c->{label}, payload => $c->{payload}, idembedded_datasets => $pk}, {returning => 'id'})->hash->{id};
            $self->pg->db->insert($dataset->{storage_entity}, {iddata => $iddata, embedding => $query_embedding});
        }
    }

    $self->render(text => 'OK');
});

# Kicks off a background job to process all input_data for a project.
$r->post('/LLM/batch_process' => sub {
     my $self = shift;

     # Query: Select input IDs where no corresponding output entry exists
     my $sql = q{
         SELECT i.id
         FROM input_data i
         LEFT JOIN output_data o ON i.id = o.idinput
         WHERE o.idinput IS NULL
     };

    # Get the list of IDs
    my $input_ids = $self->pg->db->query($sql)->hashes->map(sub { $_->{id} })->to_array;
    my $total_items = scalar @$input_ids;

    # Enqueue jobs only for the unprocessed items
    foreach my $idinput (@$input_ids) {
        $self->minion->enqueue(process_single_input => [$idinput]);
    }

    $self->render(json => {
          message => "Batch process started. Queued $total_items items (skipped inputs with existing outputs).",
    });
});

$r->post('/LLM/run_stateless/:key' => [key => qr/\d+/] => sub
{
    my $self     = shift;
    my $idprompt = $self->param('key');

    my $block = $self->pg->db->query('select blocks.id, type from blocks join blocks_catalogue on idblock =  blocks_catalogue.id where idproject = ? and outputs is null and type != 8', $idprompt)->hash;

    my $result = $self->get_result_of_block_id($block->{id}, decode 'UTF-8', $self->req->body);

    $self->render(text => $result);
});

$r->post('/LLM/run/:key' => [key=>qr/\d+/] => sub
{
    my $self    = shift;
    my $idinput = $self->param('key');
    my $input   = $self->pg->db->query(q{select * from input_data where id = ?}, $idinput)->hash;
    my $result;

    eval {
        my $block = $self->pg->db->query('select blocks.id, type from blocks join blocks_catalogue on idblock =  blocks_catalogue.id where idproject = ? and outputs is null and type != 8', $input->{idprompt})->hash;
        $result = $self->get_result_of_block_id($block->{id}, $input->{content});

        $self->pg->db->insert('output_data', {content => $result, idinput => $idinput, idprompt => $input->{idprompt}});
    };

    if (my $error = $@) {
        # The 'eval' block died. Log the real error for debugging.
        $self->log->error("Error during get_result_of_block_id: $error");
        # Send a generic error to the user.
        $self->render( json => { result => $error } );
        return;
    }

    $self->render(json => {result => $result, err => $DBI::errstr});
});

$r->post('/LLM/duplicate_prompt/:id' => [id => qr/\d+/] => sub
{
    my $self = shift;
    my $id = $self->param('id');

    # Start a transaction
    my $tx = $self->pg->db->begin;

    # 1. Duplicate the project
    my $new_project_id = $self->pg->db->query(
    'INSERT INTO projects (name) SELECT name || \' (copy)\' FROM projects WHERE id = ? RETURNING id',
    $id
    )->hash->{id};

    # 2. Get all blocks for the old project
    my $blocks = $self->pg->db->query('SELECT * FROM blocks WHERE idproject = ?', $id)->hashes;

    # 3. Create a mapping from old block IDs to new block IDs
    my %id_map;

    # 4. Duplicate each block
    for my $block (@$blocks) {
        my $old_block_id = $block->{id};
        my $new_block_id = $self->pg->db->query(
        'INSERT INTO blocks (idblock, name, connections, output_value, "originX", "originY", idproject, auxfield) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING id',
        $block->{idblock},
        $block->{name},
        $block->{connections},
        $block->{output_value},
        $block->{"originX"},
        $block->{"originY"},
        $new_project_id,
        $block->{auxfield}
        )->hash->{id};
        $id_map{$old_block_id} = $new_block_id;
    }

    # 5. Update connections in the new blocks
    for my $old_block_id (keys %id_map) {
        my $new_block_id = $id_map{$old_block_id};
        my $connections = $self->pg->db->query('SELECT connections FROM blocks WHERE id = ?', $new_block_id)->hash->{connections};

        if ($connections) {
            my $decoded_connections = decode_json($connections);
            my $new_connections = {};

            for my $key (keys %$decoded_connections) {
                my $old_target_id = $decoded_connections->{$key};
                if (exists $id_map{$old_target_id}) {
                    $new_connections->{$key} = $id_map{$old_target_id};
                } else {
                    $new_connections->{$key} = $old_target_id; # Keep old ID if not in this project
                }
            }
            $self->pg->db->query('UPDATE blocks SET connections = ? WHERE id = ?', encode_json($new_connections), $new_block_id);
        }
    }

    # Commit the transaction
    $tx->commit;

    $self->render(json => {err => $DBI::errstr, pk => $new_project_id});
});

# Export a full project definition as JSON for transfer/backup
$r->get('/LLM/project/export/:id' => [id => qr/\d+/] => sub {
    my $self = shift;
    my $id = $self->param('id');

    # 1. Fetch project details
    my $project = $self->pg->db->query('SELECT name FROM projects WHERE id = ?', $id)->hash;

    unless ($project) {
        return $self->render(status => 404, json => {error => "Project with ID $id not found."});
    }

    # 2. Fetch all blocks for the project
    # We select all columns needed to fully reconstruct the blocks.
    my $blocks = $self->pg->db->query(
                                      'SELECT id, idblock, name, connections, output_value, "originX", "originY", auxfield FROM blocks WHERE idproject = ? ORDER BY id',
                                      $id
                                      )->hashes;

    # 3. Prepare the blocks for export, renaming 'id' to 'original_id'
    # This is critical for the import process to rebuild connections correctly.
    my @exported_blocks;
    for my $block (@$blocks) {
        push @exported_blocks, {
            original_id  => $block->{id},
            idblock      => $block->{idblock},
            name         => $block->{name},
            connections  => $block->{connections},
            output_value => $block->{output_value},
            originX      => $block->{originX},
            originY      => $block->{originY},
            auxfield     => $block->{auxfield},
        };
    }

    # 4. Assemble the final export data structure
    my $export_data = {
        project => {
            name => $project->{name}
        },
        blocks => \@exported_blocks
    };

    # 5. Render as JSON
    # You can also set a Content-Disposition header to suggest a filename.
    my $filename = "patchbay_project_${id}_" . ($project->{name} =~ s/[^a-zA-Z0-9_.-]+/_/gr) . ".json";
    $self->res->headers->content_disposition("attachment; filename=\"$filename\"");

    $self->render(json => $export_data);
});

# Import a project from a JSON definition
$r->post('/LLM/project/import' => sub {
     my $self = shift;

    # 1. Get JSON data from the request body
    my $import_data = $self->req->json;

    unless ($import_data && ref($import_data) eq 'HASH' && $import_data->{project} && $import_data->{blocks}) {
        return $self->render(status => 400, json => {error => "Invalid or missing JSON payload. Expected 'project' and 'blocks' keys."});
    }

    # 2. Use a transaction for an all-or-nothing import
    my $tx = $self->pg->db->begin;

    eval {
        # 3. Create the new project and get its ID
        my $new_project_id = $self->pg->db->insert('projects',
            { name => $import_data->{project}->{name} || 'Imported Project' },
            { returning => 'id' }
        )->hash->{id};

        my %id_map; # Maps original_id from JSON to new_id in the database
        my @new_blocks_to_process; # Store info for the second pass

        # 4. First Pass: Create all blocks and build the ID map
        for my $block_data (@{ $import_data->{blocks} }) {
            my $new_block_id = $self->pg->db->insert('blocks', {
                idblock      => $block_data->{idblock},
                name         => $block_data->{name},
                connections  => '{}', # Set connections in the second pass
                # output_value might also be double-encoded, so let's be safe.
                output_value => (defined $block_data->{output_value} ? $block_data->{output_value} : ''),
                "originX"    => $block_data->{originX},
                "originY"    => $block_data->{originY},
                idproject    => $new_project_id,
                auxfield     => $block_data->{auxfield},
            }, { returning => 'id' })->hash->{id};

            $id_map{ $block_data->{original_id} } = $new_block_id;

            push @new_blocks_to_process, {
                new_id => $new_block_id,
                connections_data => $block_data->{connections}
            };
        }

        # 5. Second Pass: Update connections with the new IDs
        for my $block_to_process (@new_blocks_to_process) {
            my $connections_data = $block_to_process->{connections_data};
            
            # If connections_data is a non-empty string, try to decode it.
            if ($connections_data && !ref($connections_data)) {
                eval {
                    my $decoded = decode_json($connections_data);
                    # Only accept it if the result is a hash reference
                    $connections_data = (ref($decoded) eq 'HASH') ? $decoded : {};
                };
                if ($@) {
                    $self->log->warn("Failed to decode connections JSON string for new block " . $block_to_process->{new_id} . ". Error: $@. Ignoring connections.");
                    $connections_data = {}; # Reset to empty on failure
                }
            }

            # Skip if there are no valid connections to fix
            next unless ($connections_data && ref($connections_data) eq 'HASH' && keys %$connections_data);

            my $updated_connections = {};
            for my $key (keys %$connections_data) {
                my $old_target_id = $connections_data->{$key};
                if (exists $id_map{$old_target_id}) {
                    $updated_connections->{$key} = $id_map{$old_target_id};
                } else {
                    $self->log->warn("Could not remap connection for target ID '$old_target_id'. It was not part of this import.");
                    $updated_connections->{$key} = $old_target_id; # Keep original if not found
                }
            }

            # Update the block with the re-mapped connections, properly encoded as a JSON string for the DB
            $self->pg->db->update('blocks',
                { connections => encode_json($updated_connections) },
                { id => $block_to_process->{new_id} }
            );
        }

        # 6. Commit the transaction
        $tx->commit;

        # 7. Send success response
        $self->render(json => {
            message => 'Project imported successfully.',
            new_project_id => $new_project_id
        });

    }; # End of eval

    # 8. Handle errors
    if (my $error = $@) {
        $tx->rollback;
        $self->log->error("Project import failed: $error");
        $self->render(status => 500, json => {
            error => 'Project import failed due to an internal server error.',
            details => "$error" # Stringify the error
        });
    }
});

#
# begin: generic DBI interface (CRUD)
#
# fetch all entities

$r->get('/LLM/blocks/idproject/:key' => [key => qr/[0-9]+/i] => sub
{
    my $self = shift;
    my $key  = $self->param('key');

    $self->render(json => $self->pg->db->select('blocks', [qw/*/], {idproject => $key})->hashes);
});

$r->get('/LLM/:table'=> sub
{
    my $self    = shift;
    my $table   = $self->param('table');

    if ($table eq 'blocks')
    {
        $self->render(json => $self->pg->db->select($table, [qw/*/])->hashes);
        return;
    }

    if ($table eq 'input_data')
    {
        # Fetch all columns (*), no WHERE clause, limit to 500, newest first
        $self->render(json => $self->pg->db->select($table, undef, undef, {limit => 500, order_by => 'id DESC'})->hashes);
        return;
    }

    $self->render(json => $self->pg->db->select($table, [qw/*/])->hashes);
});

# fetch entities by key/value

$r->get('/LLM/settings/id/:key' => [key => qr/[a-z0-9\s\-_\.]+/i] => sub
{
    my $self = shift;
    my $id = $self->param('key');
    my $block = $self->pg->db->query(q{select output_value, gui_fields from blocks join blocks_catalogue on idblock = blocks_catalogue.id where blocks.id = ?}, $id)->hash;
    $block->{output_value} = '{}' unless $block->{output_value};

    my $out = $block->{gui_fields} ? decode_json($block->{output_value}) : {};
    $out->{id} = $id;
    $self->render(json => [$out]);
});

$r->put('/LLM/settings/id/:key' => [key => qr/[a-z0-9\s\-_\.]+/i] => sub
{
    my $self = shift;
    my $id = $self->param('key');
    my $block = $self->pg->db->query(q{select output_value, gui_fields from blocks join blocks_catalogue on idblock = blocks_catalogue.id where blocks.id = ?}, $id)->hash;
    $block->{output_value} = '{}' unless $block->{output_value};
    my $out = decode_json($block->{output_value});
    my $patch = $self->req->json;

    foreach my $key (keys %{$patch})
    {
        $out->{$key} = $patch->{$key};
    }

    $self->pg->db->update('blocks', {output_value => encode_json $out}, {id => $id});
    $self->render(json => {err => $DBI::errstr});
});

$r->get('/LLM/:table/:col/:key' => [col => qr/[a-z_0-9\s]+/i, key => qr/[a-z0-9\s\-_\.]+/i] => sub
{
    my $self = shift;
    $self->render(json => $self->pg->db->select($self->param('table'), [qw/*/], {$self->param('col') => $self->param('key')})->hashes);
});

# update (fixme should be patch)
$r->put('/LLM/embedded_datasets/id/:key' => [key => qr/\d+/] => sub
{
    my $self = shift;
    my $pk   = $self->param('key');
    my $u    = $self->req->json;

    $self->pg->db->update('embedded_datasets', $u, {id => $pk});

    # refetch and re-embed the data

    my $dataset = $self->pg->db->query(q{
        select embedding_models.name, storage_entity, embedding_endpoint, template from embedded_datasets
        join embedding_models on embedding_models.id = idembedding_model
        where embedded_datasets.id = ?
    }, $pk)->hash;

    if (!exists $u->{template} && !exists $u->{idembedding_model})
    {
        $self->render(json => {err => $DBI::errstr});
        return;
    }

    # if either the embedding model or the template changed, perform re-emedding of all entries
    for ($self->pg->db->select('embedded_data', [qw/*/], {idembedded_datasets => $pk})->hashes->each)
    {
        my $query_embedding = $self->get_embedding($dataset->{embedding_endpoint}, $dataset->{name}, $_->{payload}, $dataset->{template});

        $self->pg->db->delete($dataset->{storage_entity}, {iddata => $_->{id}});
        $self->pg->db->insert($dataset->{storage_entity}, {embedding => $query_embedding, iddata => $_->{id}});
    }

    $self->render(json => {err => $DBI::errstr});
});

# update (fixme should be patch)
$r->put('/LLM/:table/:pk/:key' => [key => qr/\d+/] => sub
{
    my $self    = shift;
    $self->pg->db->update($self->param('table'), $self->req->json, {$self->param('pk') => $self->param('key')});
    $self->render(json => {err => $DBI::errstr});
});

# insert
$r->post('/LLM/:table/:pk' => sub
{
    my $self    = shift;
    my $table   = $self->param('table');
    my $u       = $self->req->json || {name => 'New'};

    $u->{name}    = 'New dataset'          if !$u->{name}    && $table eq 'embedded_datasets';
    $u->{name}    = 'New prompt'           if !$u->{name}    && $table eq 'projects';
    $u->{content} = 'Content goes here...' if !$u->{content} && $table eq 'input_data';

    delete $u->{name}                                        if $table eq 'input_data';

    my $id = $self->pg->db->insert($table, $u, {returning => $self->param('pk')})->hash->{id};

    $self->render(json => {err => $DBI::errstr, pk => $id});
});

# delete
$r->delete('/LLM/:table/:pk/:key' => [key=>qr/\d+/] => sub
{
    my $self    = shift;
    my $id      = $self->param('key');
    my $table   = $self->param('table');
    $self->pg->db->delete($table, {$self->param('pk') => $id});

    $self->render(json => {err => $DBI::errstr});
});

#
# end: generic DBI interface
#

helper get_result_of_patchbay_named => sub { my ($self, $name, $input) = @_;

    my $id = $self->pg->db->query(q/
    select max(blocks.id) as id from projects
    join blocks on blocks.idproject=projects.id
    join blocks_catalogue on idblock =  blocks_catalogue.id
    where projects.name = ? and blocks_catalogue.type != 8 and outputs is null and connections != '{}'
    /, $name)->hash()->{id};

    return $self->get_result_of_block_id($id, $input);
};

helper prepare_llm_prompt => sub { my ($self, $input, $prompt_template) = @_;
    my $prompt = $prompt_template;

    if ($prompt_template =~ /_INPUT_/so)
    {
        $prompt =~ s/_INPUT_/$input/so;
    }
    elsif ($input && $prompt_template)
    {
        $prompt = "$input $prompt_template";
    }
    else
    {
        $prompt = $prompt_template ? $prompt_template : $input;
    }

    return $prompt;
};

helper get_result_of_block_id => sub { my ($self, $id, $input, $cache_dict) = @_;
    my $current_block = $self->pg->db->query('select type, connections, output_value from blocks join blocks_catalogue on idblock =  blocks_catalogue.id where blocks.id = ?', $id)->hash;
    my $conn = $current_block->{connections} ? decode_json $current_block->{connections} : {};
    my $inputs = {};
    my $result = '';

    # switch / cache have to be valuated lazily
    if ($current_block->{type} ne '16' && $current_block->{type} ne '32' && $current_block->{type} ne '39')
    {
        foreach my $key (keys %{$conn})
        {
            $inputs->{$key} = $self->get_result_of_block_id($conn->{$key}, $input, $cache_dict);
            # warn '**'.$inputs->{$key};
        }
    }

    if ($current_block->{type} eq '23') # ollama
    {
        my $settings    = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $model       = $settings->{model} || 'gemma2:9b-instruct-q8_0'; #gemma2:9b-instruct-q8_0
        my $num_ctx     = $settings->{context} || 4096;
        my $temperature = $settings->{temperature} || 0;
        my $max_gen     = $settings->{max_gen} || -1;
        my $image       = encode_base64($inputs->{Base64}, '');
        my $prompt      = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});

        my $ua = Mojo::UserAgent->new;
        $ua->inactivity_timeout(0);
        $ua->request_timeout(0);
        $ua->connect_timeout(0);

        my $url  = $settings->{endpoint} || 'http://localhost:11434/api/generate';
        my $json = {
            model => $model,
            prompt => $prompt,
            stream =>  Mojo::JSON->false,
            options =>  {
                temperature => $temperature + 0,
                num_ctx => $num_ctx + 0,
                num_predict => $max_gen + 0
            }
        };

        $json->{images} = [$image] if $image; # multimodal support

        my $res = $ua->post($url => json => $json)->result;

        if ($res->is_success)
        {
            warn $res->json->{response};
            return $res->json->{response};
        }
        else
        {
            return undef;
        }
    }
    elsif ($current_block->{type} eq '53') # xml processor
    {
        my $dom = Mojo::DOM->new($inputs->{Input});
        my $nodes = $dom->find($current_block->{output_value});

        my @results = map { $_->text } @$nodes;
        return "@results";
    }
    elsif ($current_block->{type} eq '44') # aipier generic
    {
        my $settings    = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $model       = $inputs->{model} || 'gemma-2-9b-it';
        my $max_tokens  = $settings->{max_new_tokens} || 4096;
        my $prompt      = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});
        my $stop_tokens = decode_json(encode 'UTF-8', $settings->{stop}) || [];
        my $grammar     = $settings->{grammar};

        my $params = {
            inputs => $prompt,
            parameters =>
            {
                stop => $stop_tokens,
                max_new_tokens => $max_tokens,
                seed => 123,
                repetition_penalty => 1.0
            }
        };

        if ($grammar eq '1' || $grammar eq '2') # regexp
        {
            $params->{parameters}->{grammar}->{type} = $grammar eq '1' ? 'regex' : 'json';

            my $json = decode_json(encode 'UTF-8', $settings->{grammar_text}) || {};

            foreach my $key (keys %{$json})
            {
                $params->{parameters}->{grammar}->{$key} = $json->{$key};
            }
        }
        else
        {
            $params->{parameters}->{do_sample} = Mojo::JSON->false;
        }

        my $ua = Mojo::UserAgent->new;
        $ua->inactivity_timeout(0);
        $ua->request_timeout(0);
        $ua->connect_timeout(0);
        $ua->on(start => sub {
            my ($ua, $tx) = @_;
            if (my $api_key = $ENV{API_BEARER_TOKEN}) {
                $tx->req->headers->authorization("Bearer $api_key");
            }
        });

        my $tx = $ua->post("$inference_proto://inference-api.metal.kn.uniklinik-freiburg.de/llm/$model/generate" => json => $params);
        if ($tx->res->is_error) {
          warn Dumper $tx;
        }
        my $r = $tx->res->json;

        return $r->{generated_text} if exists $r->{generated_text};
        return undef;
    }
    elsif ($current_block->{type} eq '25') # phi4, ehemals gemma-2-9b-it
    {
        my $prompt = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});

        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $result   = $self->run_llm($prompt, 'phi-4', $settings->{max_tokens}, $inputs->{SystemPrompt}, $settings->{is_nongreedy});
        warn "$prompt -> $result";
        return $result;
    }
    elsif ($current_block->{type} eq '43') # deepseek
    {
        my $prompt = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});

        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $model = 'deepseek-r1-qwen-32b';
        my $result = $self->run_llm($prompt, $model, $settings->{max_tokens}, $inputs->{SystemPrompt}, $settings->{is_nongreedy});
        warn "$prompt -> $result";
        return $result;
    }
    elsif ($current_block->{type} eq '1' || $current_block->{type} eq '13') # Text constant
    {
        return $current_block->{output_value};
    }
    elsif ($current_block->{type} eq '4' || $current_block->{type} eq '14'  || $current_block->{type} eq '23') # growl / Download
    {
        my $value = $inputs->{'Input'};

        return $value;
    }
    elsif ($current_block->{type} eq '5') # sprintf
    {
        return sprintf($current_block->{output_value}, $inputs->{Input});
    }
    elsif ($current_block->{type} eq '6') # sprintf2
    {
        return sprintf($current_block->{output_value}, $inputs->{Input1},  $inputs->{Input2});
    }
    elsif ($current_block->{type} eq '7') # sprintf3
    {
        return sprintf($current_block->{output_value}, $inputs->{Input1},  $inputs->{Input2},  $inputs->{Input3});
    }
    elsif ($current_block->{type} eq '19') # sprintf4
    {
        return sprintf($current_block->{output_value}, $inputs->{Input1},  $inputs->{Input2},  $inputs->{Input3},  $inputs->{Input4});
    }
    elsif ($current_block->{type} eq '20') # sprintf5
    {
        return sprintf($current_block->{output_value}, $inputs->{Input1},  $inputs->{Input2},  $inputs->{Input3},  $inputs->{Input4}, $inputs->{Input5});
    }
    elsif ($current_block->{type} eq '12') # http get
    {
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->request_timeout(0);
        $ua->connect_timeout(0);
        my $uri = $current_block->{output_value};
        $uri =~s/_INPUT_/$inputs->{Input}/gso;
        return  $ua->get($uri)->res->body;
    }
    elsif ($current_block->{type} eq '11') # http post
    {
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->request_timeout(0);
        $ua->connect_timeout(0);
        $ua->post($inputs->{URI} => {Accept => '*/*'} => $inputs->{Body});
    }
    elsif ($current_block->{type} eq '3') # regexp-extract
    {
        return $1 if $inputs->{'Input'} =~/$current_block->{output_value}/s;
        return undef;
    }
    elsif ($current_block->{type} eq '29') # regexp-extract2
    {
        my $regexp = sprintf($current_block->{output_value}, $inputs->{Input2});
        return $1 if $inputs->{'Input1'} =~/$regexp/s;
        return undef;
    }
    elsif ($current_block->{type} eq '22') # regexp-remove
    {
        my $ret = $inputs->{'Input'};
        $ret =~s/$current_block->{output_value}//sg;
        return $ret;
    }
    elsif ($current_block->{type} eq '16') # switch->lazy evaluation
    {
        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        return $self->get_result_of_block_id($conn->{$settings->{state} eq '1' ? 'Input2' : 'Input1'}, $input, $cache_dict);
    }
    elsif ($current_block->{type} eq '32') # gated switch->lazy evaluation
    {
        my $val1 = $self->get_result_of_block_id($conn->{'Input1'}, $input, $cache_dict);
        return $self->get_result_of_block_id($conn->{$val1 ? 'Input2' : 'Input3'}, $input, $cache_dict);
    }
    elsif ($current_block->{type} eq '17') # input
    {
        return $input;
    }
    elsif ($current_block->{type} eq '18') # json-processor
    {
        my $template = $current_block->{output_value};
        $template =~s/\binput\[(\d+)\]\[['"]([^'"]+)['"]\]/\$input->[$1]->{$2}/g; # support 'nice' python-like syntax to access arrays of hashes
        $template =~s/\binput\[['"]([^'"]+)['"]\]/\$input->{$1}/g;                # support 'nice' python-like syntax to access hashes directly
        my $result = Mojo::Template->new->vars(1)->render("<%= $template%>", {input => decode_json(encode 'UTF-8', $inputs->{'Input'})});
        chomp $result;

        return $result;
    }
    elsif ($current_block->{type} eq '28') # foreach
    {
        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my @arr = split /$settings->{split}/, $inputs->{Input};
        my @out;

        foreach my $part (@arr)
        {
            push @out, $self->get_result_of_patchbay_named($settings->{module}, $part);
        }

        return Mojo::JSON::encode_json(\@out);
    }
    elsif ($current_block->{type} eq '34') # findreplace
    {
        my $out = $inputs->{Input1};

        $out =~s/$inputs->{Input2}/$inputs->{Input3}/eg;

        return $out;
    }
    elsif ($current_block->{type} eq '39') # cache
    {
        my $cache_key = $current_block->{id};

        return $cache_dict->{$cache_key} if exists $cache_dict->{$cache_key};

        return $cache_dict->{$cache_key} = $self->get_result_of_block_id($conn->{Input}, $input, $cache_dict);
    }
    elsif ($current_block->{type} eq '41') # R
    {
        my @in = @{Mojo::JSON::decode_json($inputs->{Input})};
        my $str = join ', ', @in;
        my $prefix = 'input = c('. $str . ')';

        my $R = Statistics::R->new(shared => 1, bin => '/usr/local/bin/R');
        my $filename = Mojo::File::tempfile;
        my $RCmd = $current_block->{output_value};
        my $out;
        $R->startR;
        $R->send("library(rjson)\n$prefix\n" . $RCmd . "\nwrite(toJSON(output), '$filename')\n1");
        $out = $filename->slurp if -e $filename;
        $R->stopR;
        chomp $out;
        return $out;
    }
    elsif ($current_block->{type} eq '42') # DenseRetrieval
    {
        my $settings      = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $dataset_name  = $settings->{dataset};
        my $top_k         = $settings->{top_k};
        my $is_json       = $settings->{is_json};
        my $dataset       = $self->pg->db->query(  q{
            select embedding_models.name, embedded_datasets.id as iddataset, template, storage_entity, embedding_endpoint from embedded_datasets
            join embedding_models on embedding_models.id = idembedding_model
            where embedded_datasets.name = ?
        }, $dataset_name)->hash;

        # warn $dataset_name;
        # warn Dumper $settings;
        return undef unless $dataset;


        my $storage_entity = $dataset->{storage_entity}; # fixme: sanitize to prevent SQL injections

        return undef unless $storage_entity;

        if ($is_json)
        {
            my @ret;

            my $arr = $inputs->{Input} ? decode_json(encode 'UTF-8', $inputs->{Input}) : [];

            foreach my $part (@$arr)
            {
                my $query_embedding = $self->get_embedding($dataset->{embedding_endpoint}, $dataset->{name}, $part, $dataset->{template});
                my $sql = qq{
                    select payload, label, 1 - ($storage_entity.embedding <=> ?) AS similarity

                    from $storage_entity
                    join embedded_data on embedded_data.id = iddata
                    WHERE idembedded_datasets = ?
                    order by 3 desc limit ?
                };
                my $matches = $self->pg->db->query($sql, $query_embedding, $dataset->{iddataset}, $top_k)->hashes;
                push @ret, $matches;
            }

            return Mojo::JSON::encode_json(\@ret);
        }

        my $query_embedding = $self->get_embedding($dataset->{embedding_endpoint}, $dataset->{name}, $inputs->{Input}, $dataset->{template});

        my $sql = qq{
            select payload, label, 1 - ($storage_entity.embedding <=> ?) AS similarity

            from $storage_entity
            join embedded_data on embedded_data.id = iddata
            WHERE idembedded_datasets = ?
            order by 3 desc limit ?
        };
        my $ret = $self->pg->db->query($sql, $query_embedding, $dataset->{iddataset}, $top_k)->hashes;
        warn Dumper $ret;
        return Mojo::JSON::encode_json($ret);

        return undef;
    }
    elsif ($current_block->{type} eq '51') # global variable
    {
        return $self->pg->db->query(q{SELECT max(value) as value FROM global_variables where name = ?}, $current_block->{output_value})->hash->{value};
    }
    elsif ($current_block->{type} eq '45') # meona
    {
        my ($user, $pass) = ($inputs->{username}, $inputs->{password});
        my $piz   = $inputs->{piz};
        my $from  = $inputs->{start_date} || DateTime->now( )->subtract( days => 30 )->format_cldr('yyyy-MM-dd');
        my $until = $inputs->{end_date} || DateTime->now( )->format_cldr('yyyy-MM-dd');

        my $xml = Mojo::UserAgent->new->get("http://$user:$pass\@meonalb.ukl.uni-freiburg.de:8080/medication/dwhRest?patientId=${piz}&dateFrom=$from&dateUntil=$until")->res->body;

        return XML::XML2JSON->new()->convert($xml);
    }
    elsif ($current_block->{type} eq '46') # jq
    {
        my $input_json = $inputs->{Input};
        my $jq_filter  = $current_block->{output_value};
        my $output     = '';
        my $error      = '';

        # IPC::Open3 executes the command directly, avoiding the shell.
        # The filter is passed as a distinct argument, so it needs no quoting.
        my $pid = open3(
        my $child_in,  # Writable handle to jq's STDIN
        my $child_out, # Readable handle from jq's STDOUT
        my $child_err, # Readable handle from jq's STDERR
        'jq', $jq_filter
        );

        # Send our JSON data to the jq process.
        print { $child_in } $input_json;
        close($child_in); # Close the handle to signal End-of-File.

        # Read the entire output from jq.
        $output = do { local $/; <$child_out> };

        # Read any error messages from jq.
        $error = do { local $/; <$child_err> };

        waitpid($pid, 0);
        my $exit_code = $? >> 8;

        # Check for a non-zero exit code and report the actual error from jq.
        if ($exit_code != 0) {
            chomp $error;
            die "jq command failed with exit code: $exit_code. Error: $error";
        }

        # The output from jq is already a JSON string.
        # Chomp to remove any trailing newline from the command output.
        chomp $output;
        return $output;
    }
    elsif ($current_block->{type} eq '47') # pandoc converter (formerly unrtf)
    {
        my $settings    = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $input_data  = $inputs->{Input};
        return '' unless $input_data;

        # --- START: Base64 Autodetection Logic ---
        # This should run first, as the PDF/RTF/etc. could be Base64 encoded.
        my $test_str = $input_data;
        $test_str =~ s/\s//g; # Remove whitespace for length check

        if (length($test_str) > 4 && length($test_str) % 4 == 0 && $test_str =~ m{^[A-Za-z0-9+/]+={0,2}$}) {
            warn "Input appears to be Base64-encoded; attempting to decode.";
            my $decoded_data = MIME::Base64::decode_base64($input_data);

            if (defined $decoded_data && length $decoded_data > 0) {
                $input_data = $decoded_data;
            } else {
                warn "Base64 decoding failed or produced empty output; proceeding with original data.";
            }
        }

        # Determine the input/output formats. Use lc() on from_format for case-insensitive matching.
        my $from_format = lc($settings->{from_format} || 'rtf');
        my $to_format   = $settings->{to_format} || 'markdown';

        # --- START: PDF Pre-processing Logic ---
        # If the specified input format is 'pdf', pre-process it with pdftotext.
        if ($from_format eq 'pdf') {
            warn "Input format is 'pdf'. Pre-processing with pdftotext.";

            # Write the binary PDF data to a temporary file. Must use binmode.
            my $temp_pdf_file = Mojo::File->new(Mojo::File::tempfile(SUFFIX => '.pdf'));
            $temp_pdf_file->spurt({binmode => ':raw'}, $input_data);

            # Execute pdftotext. The trailing '-' tells it to write text to STDOUT.
            my $pdftotext_path = '/opt/homebrew/bin/pdftotext';
            my $poppler_command = "$pdftotext_path " . $temp_pdf_file->to_string . " -";
            warn "Executing Poppler: $poppler_command";

            my $extracted_text = `$poppler_command`;

            # Temp PDF file is automatically removed when $temp_pdf_file goes out of scope.

            if (defined $extracted_text && length $extracted_text > 0) {
                return $extracted_text;
            } else {
                warn "pdftotext failed or extracted no text. Aborting.";
                return "Error: Failed to extract text from the provided PDF file.";
            }
        }


        # Sanitize the format to prevent command injection. This will now sanitize
        # either the original format, or 'plain' if we converted from PDF.
        if ($from_format !~ /^[\w\+\-]+$/) {
            warn "Invalid pandoc 'from_format' specified: '$from_format'. Falling back to 'rtf'.";
            $from_format = 'rtf';
        }
        if ($to_format !~ /^[\w\+\-]+$/) {
            warn "Invalid pandoc 'to_format' specified: '$to_format'. Falling back to 'text'.";
            $to_format = 'markdown';
        }

        # Write final input data (original or text-from-pdf) to a temporary file.
        my $temp_in_file = Mojo::File->new(Mojo::File::tempfile());
        $temp_in_file->spurt($input_data);

        # Use backticks to execute pandoc and capture its STDOUT.
        my $command = "pandoc -f $from_format -t $to_format " . $temp_in_file->to_string;
        warn "Executing Pandoc: $command";
        my $output  = Encode::decode 'UTF-8', `$command`;

        # The temp file is automatically removed when $temp_in_file goes out of scope.
        return $output;
    }
    elsif ($current_block->{type} eq '48') # LLM_Claude
    {
        my $prompt = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->connect_timeout(0);

        ### FIX: Get API Key from block input instead of hardcoded secret ###
        my $api_key = $inputs->{APIKey};
        return "ERROR: API Key input is missing for Claude block." unless $api_key;

        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $max_tokens = $settings->{max_tokens} || 20000;
        my $temperature = $settings->{temperature} || 0.1;
        my $version = $settings->{version} || 'claude-2';

        my $tx = $ua->post('https://api.anthropic.com/v1/complete' => {
            'x-api-key' => $api_key,
            'content-type' => 'application/json'} => json => {
                # Send the prompt in the 'prompt' parameter
                prompt => "\n\nHuman: $prompt\n\nAssistant:",
                model => $version, max_tokens_to_sample => $max_tokens + 0, temperature => $temperature + 0.0, stop_sequences => ["\n\nHuman:"]

            });

        my $res = $tx->result;
        if ($res->is_success)
        {
            return $res->json->{completion};
        }

        warn Dumper $tx; # Log error for debugging
        return "ERROR: Claude API call failed. " . ($res->message || 'No response.');
    }
    elsif ($current_block->{type} eq '49') # OPENAI
    {
        my $prompt = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->connect_timeout(0);

        my $api_key = $inputs->{APIKey};
        return "ERROR: API Key input is missing for GPT-4 block." unless $api_key;

        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $model  = $settings->{model} || 'gpt-4-1106-preview';
        my $params =    {
            model => $model,
            temperature => $settings->{temperature} || 0.1,
            messages => [  {  role => "user", content => $prompt }  ]
        };
        $ua->on(start => sub {
            my ($ua, $tx) = @_;
            $tx->req->headers->authorization("Bearer $api_key");
        });

        my $res = $ua->post("https://api.openai.com/v1/chat/completions" => json => $params)->result;
        if ($res->is_success) {
            return $res->json->{choices}->[0]->{message}->{content};
        }

        warn Dumper $res; # Log error for debugging
        return "ERROR: GPT-4 API call failed. " . ($res->json->{error}->{message} || 'No response.');
    }
    elsif ($current_block->{type} eq '50') # LLM_Gemini
    {
        my $prompt = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # keine zertifikats-validation
        $ua->inactivity_timeout(0);
        $ua->connect_timeout(0);

        my $api_key = $inputs->{APIKey};
        return "ERROR: API Key input is missing for Gemini block." unless $api_key;

        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $model  = $settings->{model} || 'gemini-2.0-flash'; # gemini-1.5-pro

        my @parts = ({text =>  $prompt});

        if ($inputs->{Base64})
        {
            my $mime_type = 'application/pdf';

            push @parts, {inline_data => {data => $inputs->{Base64}, mime_type => $mime_type}};
        }

        my $params =    {
            contents => [{parts => \@parts }],
            generationConfig => {
                temperature => $settings->{temperature} || 0.1,
            }
        };

        my $tx = $ua->post("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$api_key" => json => $params);
        my $res = $tx->result;

        if ($res->is_success)
        {
            return $res->json->{candidates}->[0]->{content}->{parts}->[0]->{text};
        }
        else
        {
            # Provide a more useful error message back to the user
            my $error_msg = "ERROR: Gemini API call failed.";
            $error_msg .= " " . Dumper $res;

            return $error_msg;
        }
    }
    elsif ($current_block->{type} eq '54') # OpenRouter
    {
        my $prompt = $self->prepare_llm_prompt($inputs->{Input}, $inputs->{PromptTemplate});
        my $ua = Mojo::UserAgent->new;
        $ua->insecure(1); # Disable certificate validation
        $ua->inactivity_timeout(0);
        $ua->connect_timeout(0);

        my $api_key = $inputs->{APIKey};
        return "ERROR: API Key input is missing for OpenRouter block." unless $api_key;

        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};
        my $model = $settings->{model} || 'openai/gpt-4o'; # Default model, can be any model from OpenRouter

        my $params = {
            model       => $model,
            temperature => ($settings->{temperature} + 0.0) || 0.1,
            messages    => [{ role => "user", content => $prompt }]
        };

        my $tx = $ua->build_tx(
        POST => "https://openrouter.ai/api/v1/chat/completions" => {
            'Content-Type'  => 'application/json',
            'Authorization' => "Bearer $api_key",
            'HTTP-Referer'  => 'YOUR_SITE_URL',  # Optional: Replace with your site URL
            'X-Title'       => 'YOUR_SITE_NAME' # Optional: Replace with your site name
        } => json => $params
        );

        my $res = $ua->start($tx)->result;

        if ($res->is_success) {
            return $res->json->{choices}->[0]->{message}->{content};
        }

        warn Dumper $res->json; # Log error for debugging
        my $error_message = "ERROR: OpenRouter API call failed.";
        if (my $error = $res->json->{error}) {
            $error_message .= " " . $error->{message} if $error->{message};
        }
        return $error_message;
    }
    elsif ($current_block->{type} eq '52') # langextract
    {
        # --- Get static settings from the block's GUI configuration ---
        my $settings = $current_block->{output_value} ? decode_json($current_block->{output_value}) : {};

        # --- Get dynamic content directly from block inputs ---
        my $input_data      = $inputs->{Input} || '';
        return '' unless $input_data; # Exit if main input is empty

        my $model_id        = $inputs->{ModelID} || 'phi-4';
        my $examples_json   = $inputs->{ExamplesJSON} || '[]';
        my $prompt_text     = $inputs->{PromptText} || '';
        my $chat_template   = $inputs->{ChatTemplate}; # Optional

        # --- Create temporary files to hold the dynamic content ---
        my $temp_input_file    = Mojo::File->new(Mojo::File::tempfile())->spurt(encode 'UTF-8', $input_data);
        my $temp_examples_file = Mojo::File->new(Mojo::File::tempfile())->spurt(encode 'UTF-8', $examples_json);
        my $temp_prompt_file   = Mojo::File->new(Mojo::File::tempfile())->spurt(encode 'UTF-8', $prompt_text);

        # Define paths to Python executable and script
        my $python_executable = '/opt/langextract_env/bin/python';
        my $script_path       = '/usr/src/app/lang_extract.py';

        # --- Build the command with dynamic inputs as positional arguments ---
        my $command = "$python_executable '$script_path' " .
        "'" . $temp_input_file->to_string . "' " .
        "'$model_id' " .
        "'" . $temp_examples_file->to_string . "' " .
        "'" . $temp_prompt_file->to_string . "'";

        # Conditionally add the chat template file argument if content was provided
        my $temp_template_file;
        if (defined $chat_template && length $chat_template) {
            $temp_template_file = Mojo::File->new(Mojo::File::tempfile())->spurt($chat_template);
            $command .= " --chat-template-file '" . $temp_template_file->to_string . "'";
        }

        # --- Add optional arguments from the static GUI settings, with defaults ---
        my $max_workers = (defined $settings->{max_workers} && $settings->{max_workers} ne '')
        ? int($settings->{max_workers})
        : 1; # Default to 1
        $command .= " --max-workers " . $max_workers;

        my $extraction_passes = (defined $settings->{extraction_passes} && $settings->{extraction_passes} ne '')
        ? int($settings->{extraction_passes})
        : 1; # Default to 1
        $command .= " --extraction-passes " . $extraction_passes;

        # For max_char_buffer, we pass it only if set, to let the library use its internal logic if possible.
        # The Python script's default is None, so let's provide a number to avoid the TypeError.
        my $max_char_buffer = (defined $settings->{max_char_buffer} && $settings->{max_char_buffer} ne '')
        ? int($settings->{max_char_buffer})
        : 4000; # Provide a sensible default to prevent NoneType error.
        $command .= " --max-char-buffer " . $max_char_buffer;

        # Execute the command and capture its STDOUT
        warn "Running langextract command: $command";
        my $output = decode 'UTF-8', `$command 2>&1`; # Capture STDERR as well: `$command 2>&1`
        my $exit_code = $? >> 8;

        # Check for errors
        if ($exit_code != 0) {
            warn "langextract script ($command) failed with exit code $exit_code. Output: $output";
            return "Error: langextract script ($command) failed. See logs for details (exit code $exit_code. Output: $output).";
        }

        return $output;
    }

    return $result;
};

helper get_embedding => sub { my ($self, $endpoint, $model, $prompt, $template) = @_;
    my $ua = Mojo::UserAgent->new;
    $ua->insecure(1); # keine zertifikats-validation
    $ua->inactivity_timeout(0);
    $ua->request_timeout(0);
    $ua->connect_timeout(0);

    $prompt = sprintf($template, $prompt) if $template;

    if ($endpoint =~ /localhost/i)
    {
        my $query_embedding = $ua->post($endpoint => json => {model => $model, prompt => $prompt})->res->json->{embedding};
        return  '['.join(', ', @{$query_embedding}).']';
    }

    $ua->on(start => sub {
        my ($ua, $tx) = @_;
        if (my $api_key = $ENV{API_BEARER_TOKEN}) {
            $tx->req->headers->authorization("Bearer $api_key");
        }
    });

    my $tx = $ua->post($endpoint => json => {inputs => $prompt, truncate => Mojo::JSON->true});
    return '['.join(', ', @{$tx->res->json->[0]}).']';
};

helper run_llm => sub { my ($self, $prompt, $model, $max_tokens, $system_prompt, $nongreedy) = @_;
    # prompt caching is important for performance
    my $a = $self->pg->db->query(q{select response from llm_usage_log where model = ? and prompt = ? order by insertion_time desc limit 1}, $model, $prompt)->hash;
    my $txt = $a ? $a->{response} : undef;
    return $txt if $txt;

    $max_tokens = 500 unless $max_tokens;
    $max_tokens = $max_tokens + 0; # typecast to int for super strict API
    my $text = '';
    my $ua = Mojo::UserAgent->new;
    $ua->insecure(1);
    $ua->max_redirects(5);
    $ua->inactivity_timeout(0);
    $ua->request_timeout(0);
    $ua->connect_timeout(0);
    $ua->on(start => sub    {
        my ($ua, $tx) = @_;
        if (my $api_key = $ENV{API_BEARER_TOKEN}) {
            $tx->req->headers->authorization("Bearer $api_key");
        }
    });

    if ($model =~ /gemma/io)
    {
        my $effective_prompt = "<start_of_turn>user\n$prompt<end_of_turn>\n<start_of_turn>model\n";
        my $stop_tokens = ['USER: ', '</s>', '<start_of_turn>', '<end_of_turn>'];

        my $params = {
            inputs => $effective_prompt,
            parameters =>
            $nongreedy ?
            {
                stop => $stop_tokens,
                max_new_tokens => $max_tokens,
                temperature => 0.6,
                top_p => 0.1,
                repetition_penalty => 1.1,
                top_k => 40,
                truncate => 1900

            }
            :
            {
                stop => $stop_tokens,
                max_new_tokens => $max_tokens,
                do_sample => Mojo::JSON->false,
                seed => 123,
                repetition_penalty => 1.0
            }
        };

        my $tx = $ua->post("$inference_proto://inference-api.metal.kn.uniklinik-freiburg.de/llm/$model/generate" => json => $params);
        if ($tx->res->is_error) {
          warn Dumper $tx;
        }
        my $r = $tx->res->json;
        $text = $r->{generated_text} if exists $r->{generated_text};
    }
    elsif ($model =~ /phi/io)
    {
        my $effective_prompt = "<|im_start|>system<|im_sep|>\nYou are a helpful assistant.<|im_end|>\n<|im_start|>user<|im_sep|>\n$prompt<|im_end|>\n<|im_start|>assistant<|im_sep|>\n";
        my $stop_tokens = ["<|im_start|>", "<|im_end|>", "<|im_sep|>"];

        my $params = {
            inputs => $effective_prompt,
            parameters =>
            $nongreedy ?
            {
                stop => $stop_tokens,
                max_new_tokens => $max_tokens,
                temperature => 0.6,
                top_p => 0.1,
                repetition_penalty => 1.1,
                top_k => 40,
                truncate => 1900
            }
            :
            {
                stop => $stop_tokens,
                max_new_tokens => $max_tokens,
                do_sample => Mojo::JSON->false,
                seed => 123,
                repetition_penalty => 1.0
            }
        };

        my $tx = $ua->post("$inference_proto://inference-api.metal.kn.uniklinik-freiburg.de/llm/$model/generate" => json => $params);
        if ($tx->res->is_error) {
          warn Dumper $tx;
        }
        my $r = $tx->res->json;
        $text = $r->{generated_text} if exists $r->{generated_text};
    }
    elsif ($model =~ /deepseek/io)
    {
        my $params =    {
            model => $model, temperature =>  $nongreedy ? 0.1 : 0.0,
            messages => [  {  role => "user", content => $prompt }, {  role => "assistant", content => '<think>'."\n" }  ]
        };

        my $tx = $ua->post("$inference_proto://inference-api.metal.kn.uniklinik-freiburg.de/llm/$model/v1/chat/completions" => json => $params);
        if ($tx->res->is_error) {
          warn Dumper $tx;
        }
        my $res = $tx->result;

        if ($res->is_success)
        {
            $text = $res->json->{choices}->[0]->{message}->{content};
            $text = $1 if $text =~ /.+<\/think>\s+(.+)/osi;
        }
    }

    # trim whitespace
    $text =~s/\s+$//os;
    $text =~s/^\s+//os;

    $self->pg->db->insert('llm_usage_log', {model => $model, prompt => $prompt, response => $text});

    return $text;
};

$r->get('/LLM/minion/status' => sub {
    my $self = shift;

    # Aggregate minion_jobs by date (last 30 days)
    my $sql = q{
        SELECT
        created::date AS date,
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE state = 'finished') AS finished,
        COUNT(*) FILTER (WHERE state = 'failed')   AS failed,
        COUNT(*) FILTER (WHERE state = 'active')   AS active,
        COUNT(*) FILTER (WHERE state = 'inactive') AS inactive
        FROM minion_jobs
        GROUP BY created::date
        ORDER BY created::date DESC
        LIMIT 30
    };

    my $results = $self->Minion->db->query($sql)->hashes;

    # Format dates nicely if needed, or send as YYYY-MM-DD string
    $self->render(json => $results);
});

$r->post('/LLM/run_raw_sql' => sub {
     my $self = shift;

     # Get raw body content as the SQL query
     my $sql = Encode::decode('UTF-8', $self->req->body);

     unless ($sql) {
     return $self->render(json => { error => "Empty SQL query." });
    }

    my $result;
    eval {
        # Execute query and fetch results as a collection of hashes
        $result = $self->pg->db->query($sql)->hashes;
    };

    if (my $err = $@) {
        $self->app->log->error("SQL Error: $err");
        return $self->render(json => { error => "$err" });
    }

    # If it was a non-returning statement (UPDATE/DELETE), return success message
    if (!$result) {
        return $self->render(json => { message => "Query executed successfully." });
    }

    $self->render(json => $result);
});

$r->post('/LLM/run_sql_csv' => sub {
     my $self = shift;

     # Accept SQL from a form parameter named 'sql' (for browser submission)
     # or raw body (fallback)
     my $sql = $self->param('sql') || Encode::decode('UTF-8', $self->req->body);

     unless ($sql) {
         return $self->render(text => "Empty SQL query.", status => 400);
     }

    my $results;
    eval {
        $results = $self->pg->db->query($sql)->hashes;
    };

    if (my $err = $@) {
        return $self->render(text => "SQL Error: $err", status => 500);
    }

    unless ($results && @$results) {
        return $self->render(text => "No results found.", status => 204);
    }

    # Generate CSV in memory
    my $csv_string = '';
    open my $fh, '>', \$csv_string;
    my $csv = Text::CSV->new({ binary => 1, auto_diag => 1 });

    # Headers
    my @headers = keys %{$results->[0]};
    $csv->say($fh, \@headers);

    # Rows
    foreach my $row (@$results) {
        # Slice the hash to ensure column order matches headers
        $csv->say($fh, [ @{$row}{@headers} ]);
    }
    close $fh;

    # Set headers for file download
    $self->res->headers->content_type('text/csv; charset=utf-8');
    $self->res->headers->content_disposition('attachment; filename="query_result.csv"');

    $self->render(text => $csv_string);
});

###################################################################
# main()

app->config(hypnotoad => {listen => ['http://*:8888'], workers => 5, heartbeat_timeout => 12000, inactivity_timeout => 12000});

app->start;
