# Local RAG AI Agent workflow (n8n)

This document explains what the JSON in
`n8n/demo-data/workflows/local_RAG_ai_agents.json` represents and how the
workflow behaves once imported into n8n.

## What the file is

The JSON is an n8n workflow export named **Local RAG AI Agent**. It defines
nodes, their parameters, and connections for a Retrieval Augmented Generation
(RAG) chat agent plus a separate ingestion pipeline that builds a local
knowledge base.

## High-level behavior

The workflow has two paths:

- **Chat path**: accepts a chat message via a webhook or chat trigger, enriches
  it with session context from Postgres chat memory, and runs an AI Agent that
  can call a vector store tool. The response is returned to the requester.
- **Ingestion path**: watches a Google Drive folder for new or updated files,
  downloads and extracts text, splits it into chunks, embeds it, and writes
  vectors into a Qdrant collection named `documents`.

## Core nodes and roles

- **AI Agent**: orchestrates tool usage and language model responses. It
  receives the chat input and session ID from a Set node and uses memory and
  tools to answer.
- **Postgres Chat Memory**: stores and retrieves conversation history for the
  agent, allowing multi-turn context.
- **Ollama Chat Model**: provides the LLM used by the AI Agent for chat.
- **Vector Store Tool**: exposes the Qdrant vector store to the agent as a tool
  it can call to retrieve relevant documents.
- **Qdrant Vector Store**: the retrieval layer backed by Qdrant; wired with
  embeddings for similarity search.
- **Embeddings (Ollama)**: generates vector embeddings for both retrieval and
  ingestion steps.

## Chat path (request and response)

1. **Webhook** and **When chat message received** triggers accept input.
2. **Edit Fields** normalizes inputs into `chatInput` and `sessionId`.
3. **AI Agent** uses:
   - **Postgres Chat Memory** for context,
   - **Ollama Chat Model** for generation,
   - **Vector Store Tool** for retrieval.
4. **Respond to Webhook** returns the agent output.

## Ingestion path (build knowledge base)

1. **File Created** and **File Updated** watch a Google Drive folder.
2. **Set File ID** captures file and folder IDs.
3. **Clear Old Vectors** removes old vectors in Qdrant for that file ID.
4. **Download File** pulls the document and converts Google Docs to plain text.
5. **Extract Document Text** extracts text from the file.
6. **Recursive Character Text Splitter** chunks the text for embedding.
7. **Default Data Loader** attaches metadata (file_id, folder_id).
8. **Embeddings Ollama1** embeds the chunks.
9. **Qdrant Vector Store Insert** writes the embeddings into `documents`.

## Credentials and external services used

The workflow references these credential types:

- **Postgres** for chat memory storage.
- **Ollama** for chat generation and embeddings.
- **Qdrant** for vector search and storage.
- **Google Drive** for source documents and triggers.

## Notes

- The workflow is inactive by default (`"active": false`).
- The vector collection name is `documents`.
- The Clear Old Vectors node deletes by `metadata.file_id` to avoid stale data.
- Credentials created in the n8n UI are stored in Postgres (and encrypted with
  `N8N_ENCRYPTION_KEY`), not in `n8n/demo-data/credentials`. The demo directory
  is only for one-off imports.

