-- Create chat_memory table for storing conversation history
CREATE TABLE IF NOT EXISTS chat_memory (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(255) NOT NULL,
    user_id VARCHAR(255),
    message_type VARCHAR(50) NOT NULL, -- 'user' or 'assistant'
    message_content TEXT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_chat_memory_session_id ON chat_memory(session_id);
CREATE INDEX IF NOT EXISTS idx_chat_memory_timestamp ON chat_memory(timestamp);
CREATE INDEX IF NOT EXISTS idx_chat_memory_user_id ON chat_memory(user_id);

-- Create a function to get recent chat history
CREATE OR REPLACE FUNCTION get_chat_history(
    p_session_id VARCHAR(255),
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE(
    message_type VARCHAR(50),
    message_content TEXT,
    message_timestamp TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cm.message_type,
        cm.message_content,
        cm.timestamp
    FROM chat_memory cm
    WHERE cm.session_id = p_session_id
    ORDER BY cm.timestamp DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql; 