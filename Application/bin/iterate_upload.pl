#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use Getopt::Long qw(GetOptions);
use Mojo::UserAgent;
use Mojo::File;
use Encode;

# --- Configuration ---
my $upload_dir = '/upload';

# --- Command-Line Options ---
my $prompt_id;
my $filter = '*';
my $input_encoding; # <-- No default value. Will be undef if not provided.
my $host = 'http://localhost:8888';

GetOptions(
           'prompt-id=i'      => \$prompt_id,
           'filter=s'         => \$filter,
           'input-encoding=s' => \$input_encoding,
           'host=s'           => \$host,
           ) or die "Error in command line arguments.\n";

# The prompt_id is mandatory. Print usage information if it's missing.
unless ($prompt_id) {
    print <<"USAGE";
    Error: --prompt-id is a required argument.

    This script iterates over files in a directory, posting each one to a
    Mojolicious backend endpoint. It intelligently handles text and binary files.

Usage:
    $0 --prompt-id <id> [options]

    Required Options:
    --prompt-id <id>    The numeric ID of the prompt for the API endpoint.

        Optional Options:
        --filter <glob>     A glob pattern to select files (e.g., "*.txt", "report_*.csv").
        (Default: "*")
        --input-encoding <enc> Force all files to be treated as text and decoded with
        this encoding (e.g., "UTF-8", "latin1").
        If not provided, the script will auto-detect:
        - .txt, .rtf files are treated as UTF-8 text.
        - All other files are treated as binary.
        --host <url>        The base URL of the backend server.
        (Default: "http://localhost:8888")

        Examples:
        # Auto-mode: Process all files. *.txt/rtf as text, others as binary.
        $0 --prompt-id 123

        # Force-mode: Process all *.log files, treating them as latin1 text.
        $0 --prompt-id 456 --filter "*.log" --input-encoding "latin1"
        USAGE
        exit 1;
}

# --- Main Logic ---

# If an encoding is provided, check if it's supported
if (defined $input_encoding && !Encode::find_encoding($input_encoding)) {
    die "Error: Unsupported encoding '$input_encoding'.\n";
}

my $dir = Mojo::File->new($upload_dir);

# Check if the directory exists and is readable
unless (-d $dir && -r _) {
    die "Error: Directory '$upload_dir' not found or is not readable.\n";
}

# Create a single UserAgent for all requests
my $ua = Mojo::UserAgent->new;
$ua->inactivity_timeout(0); # No timeout for slow server responses
$ua->request_timeout(0);    # No timeout for the whole request

# Construct the target URL
my $url = Mojo::URL->new($host)->path("/LLM/run_stateless/$prompt_id");
print "Targeting endpoint: $url\n\n";

# Get a list of files matching the filter (excluding subdirectories)
my $files = $dir->list({dir => 0}, $filter);

if ($files->size == 0) {
    print "No files found in '$upload_dir' matching filter '$filter'.\n";
    exit 0;
}

# Iterate over each file
for my $file ($files->each) {
    print "--- Processing file: " . $file->basename . " ---\n";

    my $post_body;
    my $raw_content = $file->slurp; # Read the entire file as raw bytes

    # Decide how to handle the content based on user options and file type
    if (defined $input_encoding) {
        # FORCED MODE: User specified an encoding, so we treat it as text.
        print "  -> Treating as text (encoding forced by user: $input_encoding)\n";
        eval {
            $post_body = Encode::decode($input_encoding, $raw_content, Encode::FB_CROAK);
        };
        if ($@) {
            warn "  [ERROR] Could not decode file '" . $file->to_string . "' with encoding '$input_encoding': $@. Skipping.\n\n";
            next;
        }
    }
    elsif ($file->basename =~ /\.(txt|rtf)$/i) {
        # AUTOMATIC TEXT MODE: No encoding specified, but it's a known text extension.
        print "  -> Treating as text (auto-detected .txt/.rtf, assuming UTF-8)\n";
        eval {
            $post_body = Encode::decode('UTF-8', $raw_content, Encode::FB_CROAK);
        };
        if ($@) {
            warn "  [ERROR] Could not decode file '" . $file->to_string . "' as UTF-8: $@. Try using --input-encoding if it's different. Skipping.\n\n";
            next;
        }
    }
    else {
        # AUTOMATIC BINARY MODE: No encoding specified and not a known text extension.
        print "  -> Treating as binary\n";
        $post_body = $raw_content; # Use the raw bytes directly
    }

    # Post the file content to the endpoint
    my $tx = $ua->post($url => $post_body);

    # Check the result of the transaction
    if (my $res = $tx->result) {
        if ($res->is_success) {
            print $res->body;
        } else {
            warn "  [ERROR] Server returned an error: " . $res->code . " " . $res->message . "\n";
            warn "  Response Body: " . $res->body . "\n" if length $res->body;
        }
    } else {
        warn "  [ERROR] Connection failed: " . ($tx->error->{message} // 'Unknown error') . "\n";
    }
    print "\n--- End of response for " . $file->basename . " ---\n\n";
}

print "Batch processing complete.\n";
