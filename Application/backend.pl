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
use JQ::Lite;
use XML::XML2JSON;
use Archive::Zip;

no warnings 'uninitialized';

helper pg => sub { state $pg = Mojo::Pg->new('postgresql://docker:docker@localhost/llm_patchbay') };

my $prefix = $ENV{NB_PREFIX} || '';
my $inference_proto = $ENV{NB_PREFIX} ? 'http' : 'https';

# Check for the NB_PREFIX environment variable and set it as the URL prefix.
if ($prefix ne '') 
{
    $prefix = "/$prefix" unless $prefix =~ m{^/};
    app->static->prefix($prefix);
    app->log->info("Serving from the prefix '$prefix'");
}

sub startup {
    my $self = shift;
    $self->log->level('debug'); # Ensure debug messages are visible for UA logging
    $self->log->info("Application started and log level set to debug.");
}

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

    my $block = $self->pg->db->query('select blocks.id, type from blocks join blocks_catalogue on idblock =  blocks_catalogue.id where idproject = ? and outputs is null and type != 8', $input->{idprompt})->hash;
    my $result = $self->get_result_of_block_id($block->{id}, $input->{content});

    $self->pg->db->insert('output_data', {content => $result, idinput => $idinput, idprompt => $input->{idprompt}});

    my $o = {result => $result, err => $DBI::errstr};

    $self->render(json => $o);
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
        warn Dumper $json;

        my $res = $ua->post($url => json => $json)->result;
        warn Dumper $res;

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
    elsif ($current_block->{type} eq '45') # xml processor
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

        warn Dumper $params;

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
    elsif ($current_block->{type} eq '44') # global variable
    {
        my $sth = $self->db->prepare(qq{SELECT max(value) as value FROM global_settings where name = ?});
        $sth->execute($current_block->{output_value});

        return $sth->fetchrow_hashref()->{value};
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
    elsif ($current_block->{type} eq '46') # jq lite
    {
        my $jq = JQ::Lite->new;
        my @results = $jq->run_query($inputs->{Input}, $current_block->{output_value});
        return Mojo::JSON::encode_json(\@results);
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
        my $output  = `$command`;

        # The temp file is automatically removed when $temp_in_file goes out of scope.
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

$r->post('/LLM/upload' => sub {
    my $self = shift;
    my $upload_dir = '/tmp/upload'; # IMPORTANT: This directory must be writable by the user running the web server.

    my $uploads = $self->req->uploads('files[]');

    unless (scalar @$uploads) {
        return $self->render(status => 400, json => {error => 'No files uploaded. Please use the form field named "files[]".'});
    }

    my $dir_path = Mojo::File->new($upload_dir);
    eval {
        $dir_path->make_path unless -d $dir_path;
    };
    if ($@) {
        $self->app->log->error("Failed to create upload directory '$upload_dir': $@");
        return $self->render(status => 500, json => {error => "Server configuration error: Could not create upload directory."});
    }

    my @results;

    for my $upload (@$uploads) {
        my $filename = $upload->filename;
        my $content_type = $upload->headers->content_type;

        if ($filename =~ /\.zip$/i && ($content_type eq 'application/zip' || $content_type eq 'application/x-zip-compressed')) {
            # --- START OF THE FIX ---

            # Create a temporary file to reliably store the upload,
            # regardless of whether it's in memory or on disk initially.
            my $temp_zip_file = Mojo::File::tempfile();
            my $temp_zip_path = $temp_zip_file->to_string;

            # Move the uploaded content to our temp file. This works for both
            # Mojo::Asset::Memory and Mojo::Asset::File.
            $upload->move_to($temp_zip_path);

            # Now we can safely use our temp file path with Archive::Zip
            my $zip = Archive::Zip->new();

            if ($zip->read($temp_zip_path) != Archive::Zip::AZ_OK) {
                $self->app->log->error("Could not read zip file '$filename' from its temp path '$temp_zip_path'.");
                return $self->render(status => 500, json => {error => "Server error: Failed to read the ZIP file '$filename'."});
            }
            # --- END OF THE FIX ---

            if ($zip->extractTree('', "$upload_dir/") != Archive::Zip::AZ_OK) {
                $self->app->log->error("Failed to extract zip file '$filename' to '$upload_dir'.");
                return $self->render(status => 500, json => {error => "Server error: Failed to extract contents from '$filename'."});
            }

            $self->app->log->info("Successfully unpacked '$filename' to '$upload_dir'");
            push @results, { file => $filename, status => 'unpacked' };

        } else {
            # This logic was already correct: move the upload to its final destination.
            my $destination_path = Mojo::File->new($upload_dir, $filename);
            $upload->move_to($destination_path->to_string);

            $self->app->log->info("Successfully saved '$filename' to '$upload_dir'");
            push @results, { file => $filename, status => 'saved' };
        }
    }

    $self->render(status => 200, json => { message => "Upload process completed.", files_processed => \@results });
});

###################################################################
# main()

app->config(hypnotoad => {listen => ['http://*:8888'], workers => 5, heartbeat_timeout => 12000, inactivity_timeout => 12000});

app->start;
