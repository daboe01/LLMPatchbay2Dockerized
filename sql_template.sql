--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5 (Ubuntu 17.5-0ubuntu0.25.04.1)
-- Dumped by pg_dump version 17.5 (Ubuntu 17.5-0ubuntu0.25.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat access method';


--
-- Name: try_cast_to_jsonb(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.try_cast_to_jsonb(p_input text) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
    AS $$
BEGIN
  RETURN p_input::jsonb;
EXCEPTION
  WHEN others THEN
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.try_cast_to_jsonb(p_input text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: llm_usage_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.llm_usage_log (
    id integer NOT NULL,
    insertion_time timestamp without time zone DEFAULT now(),
    model text,
    prompt text,
    response text
);


ALTER TABLE public.llm_usage_log OWNER TO postgres;

--
-- Name: _goa_cache; Type: MATERIALIZED VIEW; Schema: public; Owner: postgres
--

CREATE TABLE public.blocks (
    id integer NOT NULL,
    idblock integer,
    name text,
    connections text,
    output_value text,
    "originX" integer,
    "originY" integer,
    idproject integer,
    auxfield text
);


ALTER TABLE public.blocks OWNER TO postgres;

--
-- Name: blocks_catalogue; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.blocks_catalogue (
    id integer NOT NULL,
    type integer,
    name text,
    inputs text,
    outputs text,
    default_value text,
    gui_xml text,
    gui_fields text,
    block_from_external integer DEFAULT 0
);


ALTER TABLE public.blocks_catalogue OWNER TO postgres;

--
-- Name: blocks_catalogue_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.blocks_catalogue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.blocks_catalogue_id_seq OWNER TO postgres;

--
-- Name: blocks_catalogue_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.blocks_catalogue_id_seq OWNED BY public.blocks_catalogue.id;


--
-- Name: blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.blocks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.blocks_id_seq OWNER TO postgres;

--
-- Name: blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.blocks_id_seq OWNED BY public.blocks.id;


--
-- Name: embedded_data; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.embedded_data (
    id integer NOT NULL,
    idembedded_datasets integer,
    label text,
    payload text
);


ALTER TABLE public.embedded_data OWNER TO postgres;

--
-- Name: embedded_data_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.embedded_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.embedded_data_id_seq OWNER TO postgres;

--
-- Name: embedded_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.embedded_data_id_seq OWNED BY public.embedded_data.id;


--
-- Name: embedded_datasets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.embedded_datasets (
    id integer NOT NULL,
    idembedding_model integer,
    name text,
    template text
);


ALTER TABLE public.embedded_datasets OWNER TO postgres;

--
-- Name: embedded_datasets_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.embedded_datasets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.embedded_datasets_id_seq OWNER TO postgres;

--
-- Name: embedded_datasets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.embedded_datasets_id_seq OWNED BY public.embedded_datasets.id;


--
-- Name: embedding_models; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.embedding_models (
    id integer NOT NULL,
    name text,
    storage_entity text,
    embedding_endpoint text,
    rest_headers text
);


ALTER TABLE public.embedding_models OWNER TO postgres;

--
-- Name: embedding_models_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.embedding_models_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.embedding_models_id_seq OWNER TO postgres;

--
-- Name: embedding_models_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.embedding_models_id_seq OWNED BY public.embedding_models.id;


--
-- Name: embeddings_1024; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.embeddings_1024 (
    id integer NOT NULL,
    iddata integer,
    embedding public.vector(1024)
);


ALTER TABLE public.embeddings_1024 OWNER TO postgres;

--
-- Name: embeddings_1024_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.embeddings_1024_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.embeddings_1024_id_seq OWNER TO postgres;

--
-- Name: embeddings_1024_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.embeddings_1024_id_seq OWNED BY public.embeddings_1024.id;


--
-- Name: embeddings_768; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.embeddings_768 (
    id integer NOT NULL,
    iddata integer,
    embedding public.vector(768)
);


ALTER TABLE public.embeddings_768 OWNER TO postgres;

--
-- Name: embeddings_768_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.embeddings_768_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.embeddings_768_id_seq OWNER TO postgres;

--
-- Name: embeddings_768_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.embeddings_768_id_seq OWNED BY public.embeddings_768.id;


--
-- Name: global_variables; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.global_variables (
    id integer NOT NULL,
    name text,
    value text
);


ALTER TABLE public.global_variables OWNER TO postgres;

--
-- Name: global_variables_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.global_variables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.global_variables_id_seq OWNER TO postgres;

--
-- Name: global_variables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.global_variables_id_seq OWNED BY public.global_variables.id;


--
-- Name: input_data; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.input_data (
    id integer NOT NULL,
    content text,
    insertion_time timestamp without time zone DEFAULT now(),
    idprompt integer,
    title text
);


ALTER TABLE public.input_data OWNER TO postgres;

--
-- Name: input_data_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.input_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.input_data_id_seq OWNER TO postgres;

--
-- Name: input_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.input_data_id_seq OWNED BY public.input_data.id;


--
-- Name: llm_usage_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.llm_usage_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.llm_usage_log_id_seq OWNER TO postgres;

--
-- Name: llm_usage_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.llm_usage_log_id_seq OWNED BY public.llm_usage_log.id;


--
-- Name: output_data; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.output_data (
    id integer NOT NULL,
    content text,
    idprompt integer,
    idinput integer,
    insertion_time timestamp without time zone DEFAULT now()
);


ALTER TABLE public.output_data OWNER TO postgres;

--
-- Name: output_data_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.output_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.output_data_id_seq OWNER TO postgres;

--
-- Name: output_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.output_data_id_seq OWNED BY public.output_data.id;


--
-- Name: projects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.projects (
    id integer NOT NULL,
    name text
);


ALTER TABLE public.projects OWNER TO postgres;

--
-- Name: projects_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.projects_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.projects_id_seq OWNER TO postgres;

--
-- Name: projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.projects_id_seq OWNED BY public.projects.id;


--
-- Name: blocks id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blocks ALTER COLUMN id SET DEFAULT nextval('public.blocks_id_seq'::regclass);


--
-- Name: blocks_catalogue id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blocks_catalogue ALTER COLUMN id SET DEFAULT nextval('public.blocks_catalogue_id_seq'::regclass);


--
-- Name: embedded_data id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embedded_data ALTER COLUMN id SET DEFAULT nextval('public.embedded_data_id_seq'::regclass);


--
-- Name: embedded_datasets id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embedded_datasets ALTER COLUMN id SET DEFAULT nextval('public.embedded_datasets_id_seq'::regclass);


--
-- Name: embedding_models id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embedding_models ALTER COLUMN id SET DEFAULT nextval('public.embedding_models_id_seq'::regclass);


--
-- Name: embeddings_1024 id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embeddings_1024 ALTER COLUMN id SET DEFAULT nextval('public.embeddings_1024_id_seq'::regclass);


--
-- Name: embeddings_768 id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embeddings_768 ALTER COLUMN id SET DEFAULT nextval('public.embeddings_768_id_seq'::regclass);


--
-- Name: global_variables id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.global_variables ALTER COLUMN id SET DEFAULT nextval('public.global_variables_id_seq'::regclass);


--
-- Name: input_data id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.input_data ALTER COLUMN id SET DEFAULT nextval('public.input_data_id_seq'::regclass);


--
-- Name: llm_usage_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_usage_log ALTER COLUMN id SET DEFAULT nextval('public.llm_usage_log_id_seq'::regclass);


--
-- Name: output_data id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.output_data ALTER COLUMN id SET DEFAULT nextval('public.output_data_id_seq'::regclass);


--
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projects ALTER COLUMN id SET DEFAULT nextval('public.projects_id_seq'::regclass);


--
-- Data for Name: blocks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.blocks (id, idblock, name, connections, output_value, "originX", "originY", idproject, auxfield) FROM stdin;
522	1	\N	\N	phi-4	0	178	25	\N
521	18	\N	\N	{"grammar_text":""}	12	116	25	\N
523	1	\N	\N	<|im_start|>system<|im_sep|>\nYou are a brilliant ophthalmologist.<|im_end|>\n<|im_start|>user<|im_sep|>\n_INPUT_<|im_end|>\n<|im_start|>assistant<|im_sep|>\n	0	48	25	\N
525	5	\N	{"Input":524}	\N	511	140	25	\N
524	34	\N	{"Input":521,"PromptTemplate":523,"model":522}	{"grammar":0,"grammar_text":"","num_generate":"10000","stop":"[\\"<|im_start|>\\", \\"<|im_end|>\\", \\"<|im_sep|>\\"]"}	282	110	25	\N
\.


--
-- Data for Name: blocks_catalogue; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.blocks_catalogue (id, type, name, inputs, outputs, default_value, gui_xml, gui_fields, block_from_external) FROM stdin;
5	4	Growl	["Input"]	\N	\N	\N	\N	0
9	8	Label	\N	\N	\N	\N	\N	0
15	14	MarkdownPDF	["Input"]	\N	\N	       <vbox>\n         <hbox>\n           <label valign="center">Diff with previous version:</label>\n           <switchButton column="perform_diff"/>\n           <hspace/>\n        </hbox>\n           <label valign="center">(Only with scratchpad)</label>\n\n      </vbox>\n	["perform_diff"]	0
6	5	Sprintf	["Input"]	["Output"]	Input is %s	\N	\N	0
7	6	Sprintf2	["Input1", "Input2"]	["Output"]	Input1 is %s and Input2 is %s	\N	\N	0
8	7	Sprintf3	["Input1", "Input2", "Input3"]	["Output"]	Input1 is %s, Input2 is and Input3 is %s	\N	\N	0
17	16	Switch	["Input1", "Input2"]	["Output"]	\N	<vbox>\n <hbox>\n    <popUpButton column="state">\n                   <popUpButtonItem title="Input 1" tag="0"/>\n                   <popUpButtonItem title="Input 2" tag="1"/>\n     </popUpButton>\n     <hspace/>\n  </hbox>\n</vbox>\n	["state"]	0
18	17	Input	\N	["Output"]	\N	       <vbox>\n<hbox>\n           <label valign="center">Data comes from the input manage on the left</label>\n           <hspace/>\n</hbox> \n     </vbox>\n	["dummy"]	0
14	13	Scratchpad	\N	["Output"]	\N	\N	\N	0
4	3	RegexpExtract	["Input"]	["Output"]	^(.+)$	\N	\N	0
19	18	JSON_Processor	["Input"]	["Output"]	input['SOME_KEY']	\N	\N	0
20	19	Sprintf4	["Input1", "Input2", "Input3", "Input4"]	["Output"]	%s\n%s\n%s\n%s	\N	\N	0
21	20	Sprintf5	["Input1", "Input2", "Input3", "Input4", "Input5"]	["Output"]	%s\n%s\n%s\n%s\n%s	\N	\N	0
12	11	HTTP-post	["URI", "Body"]	\N	\N	\N	\N	1
1	1	Text constant	\N	["Output"]	Some string	\N	\N	0
23	34	FindReplace	["Input1", "Input2", "Input3"]	["Output"]	\N	\N	\N	0
25	28	TextSplitterForeach	["Input"]	["Output"]	\N	<vbox>\n        <hbox>\n           <label halign="min" valign="center">Split by:</label>\n           <textField column="split" width="80"/>\n           <hspace/>\n        </hbox>\n        <hbox>\n           <label halign="min" valign="center">Run Module:</label>\n           <textField column="module" width="150"/>\n           <hspace/>\n        </hbox>\n</vbox>	["split", "module"]	0
26	29	RegexpExtract2	["Input1", "Input2"]	["Output"]	(\\d+): \\Q%s\\E	\N	\N	0
27	32	Switch_gated	["Input1", "Input2", "Input3"]	["Output"]	\N	\N	\N	0
28	39	Cache	["Input"]	["Output"]	\N	\N	\N	0
29	22	RegexpRemove	["Input"]	["Output"]	\N	\N	\N	0
31	41	R	["Input"]	["Output"]	output = input[order(input, decreasing = T)]	\N	\N	0
33	43	LLM_DeepSeekR1	["PromptTemplate", "Input"]	["Output"]	\N	<vbox>\n         <hbox>\n           <label valign="center">Nongreedy:</label>\n           <switchButton column="is_nongreedy"/>\n           <hspace/>\n        </hbox>\n      </vbox>	["max_tokens", "is_nongreedy"]	0
32	42	DenseRetrieval	["Input"]	["Output"]	\N	       <vbox>\n        <hbox>\n           <label halign="min" valign="center">Dataset:</label>\n           <textField column="dataset" width="150"/>\n           <hspace/>\n        </hbox>\n         <hbox>\n           <label valign="center">Top K:</label>\n           <textField column="top_k" width="50"/>\n           <hspace/>\n        </hbox>\n        <hbox>\n           <label halign="min" valign="center">JSON-Array:</label>\n           <switchButton column="is_json"/>\n           <hspace/>\n        </hbox>\n      </vbox>\n	["dataset", "top_k", "is_json"]	0
34	44	LLM_AIPIER	["model", "Input", "PromptTemplate"]	["Output"]	\N	<vbox>\n        <hbox>\n           <label halign="min" valign="center">NumOut:</label>\n           <textField column="num_generate" halign="min" width="60"/>\n           <hspace/>\n        </hbox>\n        <hbox>\n           <label halign="min" valign="center">Stop (JSON-Array):</label>\n           <textField column="stop" width="100"/>\n           <hspace/>\n        </hbox>\n\n <hbox>\n           <label halign="min" valign="center">Grammar:</label>\n    <popUpButton column="grammar">\n                   <popUpButtonItem title="None" tag="0"/>\n                   <popUpButtonItem title="Regexp" tag="1"/>\n                   <popUpButtonItem title="JSON" tag="2"/>\n     </popUpButton>\n     <hspace/>\n  </hbox>\n      <scrollView hasHorizontalScroller="NO" width="300" height="45" halign="min" valign="min">\n             <textView editable="YES" column="grammar_text" backgroundColor="white"/>\n       </scrollView>\n\n</vbox>\n	["grammar", "num_generate", "temperature", "grammar_text" ,"stop"]	0
35	53	XML_Processor	["Input"]	["Output"]	participant > actor > reference[value^="Patient/"]	\N	\N	0
13	12	HTTP-get	["Input"]	["Output"]	_INPUT_	\N	\N	1
30	25	LLM_Phi4	["PromptTemplate", "Input"]	["Output"]	\N	<vbox>\n        <hbox>\n           <label halign="min" valign="center">Max tokens:</label>\n           <textField column="max_tokens" width="50"/>\n           <hspace/>\n        </hbox>\n         <hbox>\n           <label valign="center">Nongreedy:</label>\n           <switchButton column="is_nongreedy"/>\n           <hspace/>\n        </hbox>\n      </vbox>	["max_tokens", "is_nongreedy"]	0
36	45	Meona	["username", "password", "piz", "start_date", "end_date"]	["Output"]	\N	\N	\N	0
38	46	JQ	["Input"]	["Output"]	   .[] | .name	\N	\N	0
24	23	LLM_Ollama	["PromptTemplate", "Input", "Base64"]	["Output"]	\N	<vbox>\n        <hbox>\n           <label halign="min" valign="center">Model:</label>\n           <textField column="model" width="100"/>\n           <hspace/>\n        </hbox>\n        <hbox>\n           <label halign="min" valign="center">Temperature:</label>\n           <textField column="temperature" width="50"/>\n           <hspace/>\n        </hbox>\n        <hbox>\n           <label halign="min" valign="center">Context:</label>\n           <textField column="context" width="100"/>\n           <hspace/>\n        </hbox>\n        <hbox>\n           <label halign="min" valign="center">Max gen.:</label>\n           <textField column="max_gen" width="100"/>\n           <hspace/>\n        </hbox>\n        <hbox>\n           <label halign="min" valign="center">Endpoint:</label>\n           <textField column="endpoint" width="100"/>\n           <hspace/>\n        </hbox>\n</vbox>	["model", "temperature", "context","endpoint", "max_gen"]	0
39	47	FormatConverter	["Input"]	["Output"]	\N	<vbox>\n    <hbox>\n       <label halign="min" valign="center">Input Format:</label>\n       <textField column="from_format" width="100" placeholder="rtf"/>\n       <hspace/>\n    </hbox>\n    <hbox>\n       <label valign="center">Output Format:</label>\n       <textField column="to_format" width="100" placeholder="markdown"/>\n       <hspace/>\n    </hbox>\n</vbox>	["from_format", "to_format"]	0
40	48	LLM_Claude	["Input", "PromptTemplate", "APIKey"]	["Output"]	\N	<vbox>\n        <hbox>\n           <label halign="min" valign="center">Model:</label>\n           <textField column="version" width="150" placeholder="claude-3-opus-20240229"/>\n           <hspace/>\n        </hbox>\n        <hbox>\n           <label halign="min" valign="center">Max Tokens:</label>\n           <textField column="max_tokens" width="80" placeholder="4096"/>\n           <hspace/>\n        </hbox>\n        <hbox>\n           <label halign="min" valign="center">Temperature:</label>\n           <textField column="temperature" width="80" placeholder="0.1"/>\n           <hspace/>\n        </hbox>\n</vbox>	["max_tokens", "temperature", "version"]	1
41	49	LLM_GPT4	["Input", "PromptTemplate", "APIKey"]	["Output"]	\N	<vbox>\n        <hbox>\n           <label halign="min" valign="center">Model:</label>\n           <textField column="model" width="200" placeholder="gpt-4-turbo-preview"/>\n           <hspace/>\n        </hbox>\n<hbox>\n           <label halign="min" valign="center">Temperature:</label>\n           <textField column="temperature" width="80" placeholder="0.1"/>\n           <hspace/>\n        </hbox>\n</vbox>	["model", "temperature"]	1
42	50	LLM_Gemini	["Input", "PromptTemplate", "APIKey", "Base64"]	["Output"]	\N	<vbox>\n        <hbox>\n           <label halign="min" valign="center">Model:</label>\n <textField column="model" width="200" placeholder="gemini-1.5-pro-latest"/>\n           <hspace/>\n        </hbox>\n<hbox>\n           <label halign="min" valign="center">Temperature:</label>\n           <textField column="temperature" width="80" placeholder="0.1"/>\n           <hspace/>\n        </hbox>\n           \n</vbox>	["model", "temperature"]	1
37	51	GlobalVariable	\N	["Output"]	some_name	\N	\N	0
43	52	LangExtract	["Input", "ModelID", "ExamplesJSON", "PromptText", "ChatTemplate"]	["Output"]	\N	<vbox>\n   <hbox>\n       <label halign="min" valign="center">Max Workers:</label>\n       <textField column="max_workers" width="80"/>\n       <hspace/>\n   </hbox>\n   <hbox>\n       <label halign="min" valign="center">Extraction Passes:</label>\n       <textField column="extraction_passes" width="80"/>\n       <hspace/>\n   </hbox>\n   <hbox>\n       <label halign="min" valign="center">Max Char Buffer:</label>\n       <textField column="max_char_buffer" width="80"/>\n       <hspace/>\n   </hbox>\n</vbox>	["max_workers", "extraction_passes", "max_char_buffer"]	0
44	54	LLM_OpenRouter	["Input", "PromptTemplate", "APIKey"]	["Output"]	\N	<vbox>\n        <hbox>\n           <label halign="min" valign="center">Model:</label>\n           <textField column="model" width="200" placeholder="openai/gpt-4o"/>\n           <hspace/>\n        </hbox>\n<hbox>\n           <label halign="min" valign="center">Temperature:</label>\n           <textField column="temperature" width="80" placeholder="0.1"/>\n           <hspace/>\n        </hbox>\n</vbox>	["model", "temperature"]	1
\.


--
-- Data for Name: embedding_models; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.embedding_models (id, name, storage_entity, embedding_endpoint, rest_headers) FROM stdin;
1	nomic-embed-text	public.embeddings_768	http://localhost:11434/api/embeddings	\N
2	jina/jina-embeddings-v2-base-de	public.embeddings_768	http://localhost:11434/api/embeddings	\N
3	paraphrase-multilingual	public.embeddings_768	http://localhost:11434/api/embeddings	\N
5	snowflake-arctic-embed	public.embeddings_1024	http://localhost:11434/api/embeddings	\N
4	bge-m3	public.embeddings_1024	http://localhost:11434/api/embeddings	\N
6	mxbai-embed-large	public.embeddings_1024	http://localhost:11434/api/embeddings	\N
7	jeffh/intfloat-multilingual-e5-large-instruct:f16	public.embeddings_1024	http://localhost:11434/api/embeddings	\N
8	stanus74/e5-base-sts-en-de	public.embeddings_768	http://localhost:11434/api/embeddings	\N
9	aipier-multilingual-e5-large-instruct	public.embeddings_1024	https://inference-api.metal.kn.uniklinik-freiburg.de/v1/embeddings	\N
\.


--
-- Data for Name: input_data; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.input_data (id, content, insertion_time, idprompt, title) FROM stdin;
145	how old is the universe?	2025-04-02 12:44:21.529957	25	phi4
\.


--
-- Data for Name: output_data; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.output_data (id, content, idprompt, idinput, insertion_time) FROM stdin;
1483	The age of the universe is currently estimated to be about 13.8 billion years. This estimate is based on observations of the cosmic microwave background radiation, the expansion rate of the universe (measured by the Hubble constant), and the distribution of galaxies and large-scale structures. These observations are consistent with the predictions of the Big Bang theory, which describes the universe's expansion from an extremely hot and dense initial state. The most precise measurements come from data collected by missions such as the Planck satellite, which has provided detailed observations of the cosmic microwave background.	25	145	2025-06-19 09:39:52.942221
\.


--
-- Data for Name: projects; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.projects (id, name) FROM stdin;
25	testphi4
\.


--
-- Name: blocks_catalogue_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.blocks_catalogue_id_seq', 51, true);


--
-- Name: blocks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.blocks_id_seq', 561, true);


--
-- Name: embedded_data_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.embedded_data_id_seq', 77737, true);


--
-- Name: embedded_datasets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.embedded_datasets_id_seq', 34, true);


--
-- Name: embedding_models_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.embedding_models_id_seq', 9, true);


--
-- Name: embeddings_1024_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.embeddings_1024_id_seq', 96897, true);


--
-- Name: embeddings_768_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.embeddings_768_id_seq', 13498, true);


--
-- Name: global_variables_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.global_variables_id_seq', 2, true);


--
-- Name: input_data_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.input_data_id_seq', 149, true);


--
-- Name: llm_usage_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.llm_usage_log_id_seq', 1535163, true);


--
-- Name: output_data_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.output_data_id_seq', 1483, true);


--
-- Name: projects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.projects_id_seq', 31, true);


--
-- Name: blocks_catalogue blocks_catalogue_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blocks_catalogue
    ADD CONSTRAINT blocks_catalogue_pkey PRIMARY KEY (id);


--
-- Name: blocks blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_pkey PRIMARY KEY (id);


--
-- Name: embedded_data embedded_data_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embedded_data
    ADD CONSTRAINT embedded_data_pkey PRIMARY KEY (id);


--
-- Name: embedded_datasets embedded_datasets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embedded_datasets
    ADD CONSTRAINT embedded_datasets_pkey PRIMARY KEY (id);


--
-- Name: embedding_models embedding_models_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embedding_models
    ADD CONSTRAINT embedding_models_pkey PRIMARY KEY (id);


--
-- Name: embeddings_1024 embeddings_1024_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embeddings_1024
    ADD CONSTRAINT embeddings_1024_pkey PRIMARY KEY (id);


--
-- Name: embeddings_768 embeddings_768_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embeddings_768
    ADD CONSTRAINT embeddings_768_pkey PRIMARY KEY (id);


--
-- Name: global_variables global_variables_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.global_variables
    ADD CONSTRAINT global_variables_pkey PRIMARY KEY (id);


--
-- Name: input_data input_data_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.input_data
    ADD CONSTRAINT input_data_pkey PRIMARY KEY (id);


--
-- Name: llm_usage_log llm_usage_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_usage_log
    ADD CONSTRAINT llm_usage_log_pkey PRIMARY KEY (id);


--
-- Name: output_data output_data_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.output_data
    ADD CONSTRAINT output_data_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: blocks blocks_idblock_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_idblock_fkey FOREIGN KEY (idblock) REFERENCES public.blocks_catalogue(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: embedded_data embedded_data_idembedded_datasets_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embedded_data
    ADD CONSTRAINT embedded_data_idembedded_datasets_fkey FOREIGN KEY (idembedded_datasets) REFERENCES public.embedded_datasets(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: embedded_datasets embedded_datasets_idembedding_model_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embedded_datasets
    ADD CONSTRAINT embedded_datasets_idembedding_model_fkey FOREIGN KEY (idembedding_model) REFERENCES public.embedding_models(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: embeddings_1024 embeddings_1024_iddata_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embeddings_1024
    ADD CONSTRAINT embeddings_1024_iddata_fkey FOREIGN KEY (iddata) REFERENCES public.embedded_data(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: embeddings_768 embeddings_768_iddata_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.embeddings_768
    ADD CONSTRAINT embeddings_768_iddata_fkey FOREIGN KEY (iddata) REFERENCES public.embedded_data(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: output_data output_data_idinput_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.output_data
    ADD CONSTRAINT output_data_idinput_fkey FOREIGN KEY (idinput) REFERENCES public.input_data(id) ON UPDATE CASCADE ON DELETE CASCADE;



--
-- PostgreSQL database dump complete
--

-- 1. Die neue Tabelle für die Block-Versionen (Text Constants etc.)
CREATE TABLE public.blocks_versions (
    id SERIAL PRIMARY KEY,
    block_id INTEGER NOT NULL,
    output_value TEXT,
    content_hash TEXT NOT NULL,
    changed_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
    
    CONSTRAINT fk_blocks_versions_blocks 
        FOREIGN KEY (block_id) 
        REFERENCES public.blocks(id) ON DELETE CASCADE
);

ALTER TABLE public.blocks_versions OWNER TO postgres;

-- 2. Die Trigger-Funktion für die blocks-Tabelle
CREATE OR REPLACE FUNCTION public.log_blocks_version()
RETURNS TRIGGER AS $$
BEGIN
    -- Wir prüfen hier, ob sich 'output_value' geändert hat
    IF (TG_OP = 'INSERT') OR 
       (TG_OP = 'UPDATE' AND NEW.output_value IS DISTINCT FROM OLD.output_value) THEN
       
        INSERT INTO public.blocks_versions (
            block_id, 
            output_value, 
            content_hash
        ) VALUES (
            NEW.id,
            NEW.output_value,
            encode(digest(COALESCE(NEW.output_value, ''), 'sha256'), 'hex')
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER FUNCTION public.log_blocks_version() OWNER TO postgres;

-- 3. Den Trigger an die blocks-Tabelle binden
CREATE TRIGGER trigger_blocks_versioning
AFTER INSERT OR UPDATE ON public.blocks
FOR EACH ROW
EXECUTE FUNCTION public.log_blocks_version();
