# LLMPatchbay: Visual AI Workflow Engine

LLMPatchbay is a powerful workhorse for building visual, block-based data processing and AI pipelines. It uses a "patch bay" metaphor, allowing you to connect various components—like LLM providers, databases, and custom logic—to create complex and repeatable workflows **and expose these via a RESTful API**.

This project is packaged as a self-contained Docker image that includes the Cappuccino based GUI, the Perl/Mojolicious backend, a PostgreSQL server with `pgvector`, and an R environment.

## ✨ Features

*   **Visual Workflow Engine:** A polished UI where you can connect processing blocks, craft prompts and evaluate all this in a playground.
*   **LLM Integration:**
    *   Connect to local models via **Ollama** (optional).
    *   Integrate with the AI-PIER inference API.
*   **Vector Search (RAG):**
    *   Store and manage embedding datasets using `pgvector`.
    *   Perform dense retrieval (similarity search) for RAG pipelines.
*   **Rich Data Processing Blocks:**
    *   Text manipulation (sprintf, regex), data fetching (HTTP), parsing (JSON, XML), and statistical analysis with **R**.
*   **Self-Contained & Persistent:** Runs in a single Docker container with persistent database storage.

## 🚀 Getting Started with Docker

### 1. Build the Docker Image

From the root of the project, run the build command. This will install all dependencies, set up the PostgreSQL server, and initialize the database schema.

```bash
docker build . -t patchbay
```

### 2. Run the Container (with Persistent Data)

To ensure your database data **is not lost** when the container stops or restarts, you must run it with a named volume. This command maps a volume on your host machine to the PostgreSQL data directory inside the container.

```bash
docker run -d \
  --name patchbay-app \
  -p 8888:8888 \
  -v patchbay-data:/var/lib/postgresql/17/main \
  -e API_BEARER_TOKEN="your_secret_api_key_here" \
  patchbay
```
*   `-d`: Run in detached mode (in the background).
*   `--name patchbay-app`: Give the container a memorable name.
*   `-p 8888:8888`: Map the container's port to your local machine.
*   `-v patchbay-data:/var/lib/postgresql/17/main`: **Crucial!** This creates a persistent volume named `patchbay-data` for the database.
*   `-e API_BEARER_TOKEN="..."`: Sets your API key as an environment variable for AI-PIER access.

### 3. Access The Application
Open your browser and navigate to:
**[http://127.0.0.1:8888/Frontend/index.html](http://127.0.0.1:8888/Frontend/index.html)**

To see logs from the running container:
```bash
docker logs -f patchbay-app
```

---

## ⚙️ Configuration

### Data Persistence

The `-v patchbay-data:/var/lib/postgresql/17/main` argument in the `docker run` command is essential. It tells Docker to store the database files outside the container's ephemeral filesystem. Without it, **all data will be lost** when you remove the container.

### Enabling Ollama Support

The `Dockerfile` is prepared for Ollama integration, but it is commented out by default. To enable it:

1.  **Edit your `Dockerfile`:** Uncomment the lines related to Ollama installation.
    ```dockerfile
    # FROM:
    # RUN curl -fsSL https://ollama.com/install.sh | sh
    # COPY install_ollama.sh /app
    # RUN /app/install_ollama.sh

    # TO:
    RUN curl -fsSL https://ollama.com/install.sh | sh
    COPY install_ollama.sh /app
    RUN /app/install_ollama.sh

    ```
2.  **Re-build the Image:** Add models to install_ollama.sh as needed. Then rebuild the image for the change to take effect.
    ```bash
    docker build . -t patchbay
    ```
---

## 🔌 API Documentation

The LLMPatchbay backend exposes a comprehensive RESTful API for programmatically controlling workflows, managing data, and interacting with the system's components. All API endpoints are prefixed with `/LLM`.

---

### Workflow Execution

These endpoints are used to run the pipelines you build in the visual editor.

#### Run a pipeline and save the result
Executes a pre-defined pipeline using an entry from the `input_data` table and stores the output in `output_data`.

*   **Endpoint:** `POST /LLM/run/:key`
*   **Description:** Triggers a full run of the pipeline associated with the input data record.
*   **URL Parameters:**
    *   `:key` (integer): The primary key (`id`) of the record in the `input_data` table.
*   **Example:**
    ```bash
    # Run the pipeline for the input data with id=123
    curl -X POST http://127.0.0.1:8888/LLM/run/123
    ```

#### Run a pipeline statelessly
Executes a pipeline with a given input without saving the result to the database. This is useful for integrating the workflows into your own applications.

*   **Endpoint:** `POST /LLM/run_stateless/:key`
*   **Description:** Runs a prompt/pipeline directly with the provided request body as the input.
*   **URL Parameters:**
    *   `:key` (integer): The primary key (`id`) of the prompt/pipeline.
*   **Request Body:** The raw input text for the pipeline.
*   **Example:**
    ```bash
    # Execute prompt with id=45 and provide "What is the capital of France?" as input
    curl -X POST \
      -H "Content-Type: text/plain" \
      -d "What is the capital of France?" \
      http://127.0.0.1:8888/LLM/run_stateless/45
    ```

---

### Dataset & Vector Management (RAG)

These endpoints manage datasets used for Retrieval-Augmented Generation (RAG).

#### Find similar documents in a dataset
Performs a vector similarity search against a specified dataset.

*   **Endpoint:** `POST /LLM/get_matches_from_dataset_named/:name`
*   **Description:** Embeds the request body text and finds the most similar entries in the dataset.
*   **URL Parameters:**
    *   `:name` (string): The name of the dataset to search in.
    *   `top_k` (integer, optional, default=1): The number of top matches to return.
*   **Request Body:** The raw query text to find matches for.
*   **Returns:** A JSON array of matching documents, including their payload, label, and similarity score.
*   **Example:**
    ```bash
    # Find the top 3 documents in 'medical_reports' dataset similar to the query
    curl -X POST \
      -d "Patient shows symptoms of high fever and cough" \
      "http://127.0.0.1:8888/LLM/get_matches_from_dataset_named/medical_reports?top_k=3"
    ```

#### Import data into a dataset
Bulk-imports data from a CSV file into an embedding dataset. This triggers the embedding process for each new entry.

*   **Endpoint:** `POST /LLM/import_embedding_dataset/:pk`
*   **Description:** Processes a CSV file (semicolon-separated) with `label` and `payload` columns.
*   **URL Parameters:**
    *   `:pk` (integer): The ID of the dataset to import into.
    *   `preserve=1` (optional): If set, skips importing rows that are duplicates (based on label and payload).
    *   `remove=1` (optional): If set, deletes rows from the database that match the CSV content instead of adding them.
*   **Request Body:** The CSV data.
*   **Example:**
    ```bash
    # Import data from data.csv into dataset 1, skipping duplicates
    curl -X POST \
      --header "Content-Type: text/csv" \
      --data-binary "@path/to/data.csv" \
      "http://127.0.0.1:8888/LLM/import_embedding_dataset/1?preserve=1"
    ```

#### Retrieve all data from a dataset
*   **Endpoint:** `GET /LLM/get_data_from_dataset/:dataset_name`
*   **Example:** `curl http://127.0.0.1:8888/LLM/get_data_from_dataset/medical_reports`

#### Retrieve a specific data point by label
*   **Endpoint:** `GET /LLM/get_payload_for_label_from_dataset/:label/:dataset_name`
*   **Example:** `curl http://127.0.0.1:8888/LLM/get_payload_for_label_from_dataset/report-abc/medical_reports`

---

### Specialized Endpoints

These are specific endpoints for handling complex logic that doesn't fit the generic CRUD pattern.

#### Update an embedding dataset (and trigger re-embedding)
*   **Endpoint:** `PUT /LLM/embedded_datasets/id/:key`
*   **Description:** Updates a dataset's properties. **Important:** If the `template` or `idembedding_model` is changed, this API call will automatically trigger a re-embedding of all data points within that dataset. This can be a long-running operation.
*   **Example:**
    ```bash
    # Change the template for dataset 2, triggering a re-embedding
    curl -X PUT -H "Content-Type: application/json" \
      -d '{"template": "New search query template: %s"}' \
      http://127.0.0.1:8888/LLM/embedded_datasets/id/2
    ```
    
