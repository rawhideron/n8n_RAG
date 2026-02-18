# PostgreSQL Chat Memory Setup Guide

## Step 1: Set up the Database

1. **Connect to your PostgreSQL database:**
   ```bash
   docker exec -it self-hosted-ai-starter-kit_postgres_1 psql -U $POSTGRES_USER -d $POSTGRES_DB
   ```

2. **Run the SQL setup script:**
   ```sql
   -- Copy and paste the contents of n8n/demo-data/chat_memory_setup.sql
   ```

## Step 2: Configure PostgreSQL Credentials in n8n

1. **Go to n8n** (http://localhost:5678)
2. **Navigate to Settings → Credentials**
3. **Add new PostgreSQL credentials:**
   - **Name**: `PostgreSQL`
   - **Host**: `postgres` (internal Docker network)
   - **Database**: `your_database_name`
   - **User**: `your_postgres_user`
   - **Password**: `your_postgres_password`
   - **Port**: `5432`

## Step 3: Import the Workflow

1. **In n8n, go to Workflows**
2. **Click "Import from file"**
3. **Select**: `n8n/demo-data/workflows/chat_with_memory.json`
4. **Update the credentials** to match your PostgreSQL setup

## Step 4: Test the Chat Memory

1. **Activate the workflow**
2. **Send a test message** via the webhook
3. **Check the database** to see stored messages:
   ```sql
   SELECT * FROM chat_memory ORDER BY timestamp DESC LIMIT 10;
   ```

## How it Works

1. **Chat Trigger** - Receives incoming messages
2. **Get Chat History** - Retrieves previous conversation context
3. **Build Conversation Context** - Combines history with current message
4. **Ollama Chat Model** - Generates response using context
5. **Save User Message** - Stores the user's message
6. **Save Assistant Response** - Stores the AI's response
7. **Get Full History** - Returns complete conversation history

## Customization Options

### Session Management
- **Session ID**: Use user ID, conversation ID, or custom identifier
- **History Length**: Adjust the number of messages to include in context
- **Memory Expiry**: Add timestamp filtering for older conversations

### Enhanced Features
- **User Profiles**: Store user preferences and settings
- **Conversation Analytics**: Track usage patterns
- **Multi-turn Context**: Include system prompts and instructions

## Troubleshooting

### Common Issues:
1. **Database Connection**: Ensure PostgreSQL credentials are correct
2. **Table Not Found**: Run the SQL setup script
3. **Permission Errors**: Check database user permissions
4. **Memory Issues**: Monitor conversation length and context size

### Debug Queries:
```sql
-- Check if table exists
SELECT * FROM information_schema.tables WHERE table_name = 'chat_memory';

-- View recent conversations
SELECT session_id, COUNT(*) as message_count 
FROM chat_memory 
GROUP BY session_id 
ORDER BY MAX(timestamp) DESC;

-- Check for errors
SELECT * FROM chat_memory WHERE message_content LIKE '%error%';
``` 