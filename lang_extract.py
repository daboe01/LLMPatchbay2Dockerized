#!/usr/bin/env python3
"""
A script to perform single-pass, non-parallel structured information extraction
using the langextract library and a TGI model from the Freiburg Uniklinik API.

This script outputs the full extraction result as a JSONL string to standard
output, making it suitable for command-line pipelines.
"""

import argparse
import json
import logging
import os
import sys

try:
    import langextract as lx
    from langextract.core import exceptions as lx_exceptions
    from langextract.data import AnnotatedDocument
except ImportError:
    # Use stderr for error messages
    print("FATAL: The 'langextract' library is not installed. Please install it using 'pip install langextract'.", file=sys.stderr)
    sys.exit(1)

# Configure logging to output to stderr, keeping stdout clean for results
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(name)s - %(message)s',
    stream=sys.stderr  # Direct logs to stderr
)
logger = logging.getLogger(__name__)

def load_from_file(filepath, is_json=False):
    """Loads content from a specified file, handling potential errors."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return json.load(f) if is_json else f.read()
    except FileNotFoundError:
        logger.error(f"FATAL: The file was not found at '{filepath}'")
        sys.exit(1)
    except json.JSONDecodeError:
        logger.error(f"FATAL: Could not decode JSON from the file at '{filepath}'")
        sys.exit(1)
    except Exception as e:
        logger.error(f"FATAL: An unexpected error occurred while reading '{filepath}': {e}")
        sys.exit(1)

def main():
    """Main function to configure and run the extraction process."""
    parser = argparse.ArgumentParser(
        description="Extract structured information and print the resulting JSONL to stdout.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("text_file", help="The path to the file containing the text to process.")
    parser.add_argument("model_id", help="The model ID to use (e.g., 'mistralai/Mistral-7B-Instruct-v0.2').")
    parser.add_argument("examples_file", help="The path to the JSON file with example specifications.")
    parser.add_argument("prompt_file", help="The path to the file containing the prompt.")
    parser.add_argument(
        "--chat-template-file",
        help="Optional path to a file containing a chat template with a {prompt} placeholder."
    )
    parser.add_argument(
        "--max-char-buffer",
        type=int,
        default=None,
        help="The maximum character size for text chunks."
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=1,
        help="The number of parallel worker threads to use."
    )
    parser.add_argument(
        "--extraction-passes",
        type=int,
        default=1,
        help="The number of extraction passes to perform."
    )
    # NEW ARGUMENT FOR TIMEOUT
    parser.add_argument(
        "--timeout",
        type=int,
        default=9000,
        help="The HTTP request timeout in seconds (default: 300)."
    )
    args = parser.parse_args()

    # --- 1. Load Input Data ---
    logger.info("Loading input text, examples, and prompt from files...")
    input_text = load_from_file(args.text_file)
    examples_data = load_from_file(args.examples_file, is_json=True)
    prompt = load_from_file(args.prompt_file)

    if isinstance(examples_data, dict):
        examples_data = [examples_data]

    examples = [
        lx.data.ExampleData(
            text=example['text'],
            extractions=[
                lx.data.Extraction(
                    extraction_class=ext['extraction_class'],
                    extraction_text=ext['extraction_text'],
                    attributes=ext.get('attributes', {})
                ) for ext in example['extractions']
            ]
        ) for example in examples_data
    ]

    # --- 2. Configure Model Connection ---
    api_token = os.environ.get("API_BEARER_TOKEN")

    base_url = f"http://inference-api.metal.kn.uniklinik-freiburg.de/llm/{args.model_id}/"

    model_params = {
        "base_url": base_url,
        "api_key": api_token,
        "temperature": 0.01
    }

    if args.chat_template_file:
        logger.info(f"Loading chat template from '{args.chat_template_file}'...")
        model_params['chat_template'] = load_from_file(args.chat_template_file)

    model_params['timeout'] = args.timeout

    prefixed_model_id = f"tgi::{args.model_id}"

    # --- 3. Run Extraction ---
    logger.info(f"Running extraction with model '{args.model_id}'...")
    logger.info(f"Connecting to TGI server via base URL: {base_url}")
    logger.info(f"Timeout set to {args.timeout} seconds.")

    try:
        # Added 'timeout' parameter here
        result: AnnotatedDocument = lx.extract(
            text_or_documents=input_text,
            prompt_description=prompt,
            examples=examples,
            model_id=prefixed_model_id,
            language_model_params=model_params,
            use_schema_constraints=True,
            fence_output=False,
            max_char_buffer=args.max_char_buffer,
            max_workers=args.max_workers,
            extraction_passes=args.extraction_passes
        )
        logger.info("Extraction successful!")

    except lx_exceptions.InferenceConfigError as e:
        logger.error(f"\nExtraction failed. Error: {e}")
        logger.error("\n--- TROUBLESHOOTING ---\n- Is your provider installed correctly (`pip install -e .`)?\n- Does your provider's `@registry.register` pattern match?")
        sys.exit(1)
    except Exception as e:
        logger.error(f"\nAn unexpected error occurred: {e}", exc_info=True)
        sys.exit(1)

    # --- 4. Serialize Result to JSONL and Output to Stdout ---
    logger.info("Writing JSONL result to standard output...")

    # Manually construct the list of extractions with calculated spans
    extractions_list = []
    for ext in result.extractions:
        start_index = result.text.find(ext.extraction_text)
        span = []
        if start_index != -1:
            # If the text is found, calculate the start and end of the span
            end_index = start_index + len(ext.extraction_text)
            span = [start_index, end_index]
        else:
            # Log a warning if an extraction's text can't be found in the source
            logger.warning(f"Could not find span for extraction: '{ext.extraction_text}'")

        extractions_list.append({
            "extraction_class": ext.extraction_class,
            "extraction_text": ext.extraction_text,
            "span": span,
            "attributes": ext.attributes,
        })

    # Combine the source text and the processed extractions into a final dictionary
    result_dict = {
        "text": result.text,
        "extractions": extractions_list,
    }

    # Dump the dictionary to a JSON string (a single line for JSONL format)
    jsonl_output = json.dumps(result_dict, ensure_ascii=False)
    print(jsonl_output)

if __name__ == "__main__":
    main()
