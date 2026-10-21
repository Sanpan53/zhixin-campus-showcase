-- ================================================================
-- 知新校园 · 数据库表结构（部署初始化脚本）
-- 面试展示版：仅包含表结构，不包含业务源码与真实数据
-- 执行顺序：01-schema.sql → 02-seed.sql
-- ================================================================

-- 启用 PGVector 扩展（向量存储依赖）
CREATE EXTENSION IF NOT EXISTS vector;

-- ================================================================
-- 1. 知识库表
-- ================================================================
CREATE TABLE kb_knowledge_base (
    id              BIGSERIAL PRIMARY KEY,
    name            VARCHAR(100)    NOT NULL,
    description     TEXT,
    department_id   VARCHAR(50)     NOT NULL,
    is_public       BOOLEAN         NOT NULL DEFAULT FALSE,
    created_by      BIGINT          NOT NULL,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN         NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE kb_knowledge_base IS '知识库，一个院系或处室可以有多个知识库';
CREATE INDEX idx_kb_department ON kb_knowledge_base(department_id) WHERE is_deleted = FALSE;

-- ================================================================
-- 2. 知识库权限表
-- ================================================================
CREATE TABLE kb_permission (
    id              BIGSERIAL PRIMARY KEY,
    kb_id           BIGINT          NOT NULL,
    subject_type    VARCHAR(20)     NOT NULL,
    subject_id      VARCHAR(50)     NOT NULL,
    permission      VARCHAR(20)     NOT NULL,
    granted_by      BIGINT          NOT NULL,
    granted_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    UNIQUE (kb_id, subject_type, subject_id)
);

CREATE INDEX idx_permission_subject ON kb_permission(subject_type, subject_id);

-- ================================================================
-- 3. 文档表
-- ================================================================
CREATE TABLE kb_document (
    id              BIGSERIAL PRIMARY KEY,
    kb_id           BIGINT          NOT NULL,
    file_name       VARCHAR(255)    NOT NULL,
    file_type       VARCHAR(20)     NOT NULL,
    file_size       BIGINT          NOT NULL,
    minio_path      VARCHAR(500)    NOT NULL,
    document_type   VARCHAR(20)     NOT NULL DEFAULT 'AUTO',
    resolved_document_type VARCHAR(20),
    qa_valid_count  INT             NOT NULL DEFAULT 0,
    qa_error_count  INT             NOT NULL DEFAULT 0,
    qa_warning_count INT            NOT NULL DEFAULT 0,
    qa_report       TEXT,
    status          VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
    error_msg       TEXT,
    chunk_count     INT             DEFAULT 0,
    token_count     INT             DEFAULT 0,
    version         INT             NOT NULL DEFAULT 1,
    uploaded_by     BIGINT          NOT NULL,
    uploaded_at     TIMESTAMP       NOT NULL DEFAULT NOW(),
    indexed_at      TIMESTAMP,
    is_deleted      BOOLEAN         NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE kb_document IS '上传到知识库的文档，一个文档对应多个分块';
COMMENT ON COLUMN kb_document.version IS '重建索引时递增的文档版本号';
COMMENT ON COLUMN kb_document.document_type IS '上传时选择的文档类型：AUTO / NORMAL / QA';
COMMENT ON COLUMN kb_document.qa_report IS 'QA 识别报告 JSON；格式异常不会静默丢失';

CREATE INDEX idx_doc_kb_id ON kb_document(kb_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_doc_status ON kb_document(status) WHERE is_deleted = FALSE;

-- ================================================================
-- 4. 文档分块表（核心表，含向量字段）
-- ================================================================
CREATE TABLE kb_doc_chunk (
    id              BIGSERIAL PRIMARY KEY,
    doc_id          BIGINT          NOT NULL,
    kb_id           BIGINT          NOT NULL,
    chunk_index     INT             NOT NULL,
    content         TEXT            NOT NULL,
    content_tsv     TSVECTOR,
    embedding       VECTOR(1024)    NOT NULL,
    page_num        INT,
    section_title   VARCHAR(500),
    token_count     INT             NOT NULL DEFAULT 0,
    doc_version     INT             NOT NULL,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE kb_doc_chunk IS '文档分块表，每条记录是一个可检索的最小单元';
COMMENT ON COLUMN kb_doc_chunk.content_tsv IS '全文检索向量，由触发器自动更新';
COMMENT ON COLUMN kb_doc_chunk.doc_version IS '与文档版本号对应，重建索引后清理旧版本';

-- 向量检索索引（HNSW）
CREATE INDEX idx_chunk_embedding ON kb_doc_chunk
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 128);

-- 全文检索索引
CREATE INDEX idx_chunk_content_tsv ON kb_doc_chunk USING GIN (content_tsv);

-- 多院系 / 多知识库过滤索引
CREATE INDEX idx_chunk_kb_id ON kb_doc_chunk(kb_id);
CREATE INDEX idx_chunk_doc_id ON kb_doc_chunk(doc_id);

-- 触发器：自动维护全文检索向量
CREATE OR REPLACE FUNCTION update_chunk_tsv()
RETURNS TRIGGER AS $$
BEGIN
    NEW.content_tsv := to_tsvector('simple', NEW.content);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_chunk_tsv
    BEFORE INSERT OR UPDATE OF content
    ON kb_doc_chunk
    FOR EACH ROW
    EXECUTE FUNCTION update_chunk_tsv();

-- ================================================================
-- 5. 索引任务表（异步索引状态管理）
-- ================================================================
CREATE TABLE kb_index_task (
    id              BIGSERIAL PRIMARY KEY,
    doc_id          BIGINT          NOT NULL,
    task_type       VARCHAR(20)     NOT NULL DEFAULT 'INDEX',
    status          VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
    retry_count     INT             NOT NULL DEFAULT 0,
    max_retry       INT             NOT NULL DEFAULT 3,
    error_msg       TEXT,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    started_at      TIMESTAMP,
    finished_at     TIMESTAMP
);

CREATE INDEX idx_task_status ON kb_index_task(status, created_at);
CREATE INDEX idx_task_doc_id ON kb_index_task(doc_id);

-- ================================================================
-- 6. 对话会话表
-- ================================================================
CREATE TABLE kb_chat_session (
    id              VARCHAR(36)     PRIMARY KEY,
    user_id         BIGINT          NOT NULL,
    kb_ids          TEXT            NOT NULL,
    title           VARCHAR(200),
    message_count   INT             NOT NULL DEFAULT 0,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    last_active_at  TIMESTAMP       NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN         NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_session_user ON kb_chat_session(user_id, last_active_at DESC)
    WHERE is_deleted = FALSE;

-- ================================================================
-- 7. 对话消息表
-- ================================================================
CREATE TABLE kb_chat_message (
    id              BIGSERIAL PRIMARY KEY,
    session_id      VARCHAR(36)     NOT NULL,
    role            VARCHAR(20)     NOT NULL,
    content         TEXT            NOT NULL,
    sources         JSONB,
    token_count     INT             DEFAULT 0,
    latency_ms      INT             DEFAULT 0,
    feedback        SMALLINT,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN kb_chat_message.sources IS
    'JSON 格式：[{"docId":1,"docName":"手册.pdf","chunkId":100,"pageNum":5,"excerpt":"...","score":0.92}]';

CREATE INDEX idx_message_session ON kb_chat_message(session_id, created_at);

-- ================================================================
-- 8. 用户反馈表（点赞/点踩）
-- ================================================================
CREATE TABLE kb_answer_feedback (
    id              BIGSERIAL PRIMARY KEY,
    message_id      BIGINT          NOT NULL,
    user_id         BIGINT          NOT NULL,
    feedback        SMALLINT        NOT NULL,
    comment         TEXT,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, user_id)
);

-- ================================================================
-- 9. RAG 评估数据集与结果表
-- ================================================================
CREATE TABLE kb_eval_dataset (
    id              BIGSERIAL PRIMARY KEY,
    kb_id           BIGINT          NOT NULL,
    question        TEXT            NOT NULL,
    expected_answer TEXT,
    expected_chunk_ids  BIGINT[],
    created_by      BIGINT          NOT NULL,
    created_at      TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE TABLE kb_eval_result (
    id              BIGSERIAL PRIMARY KEY,
    dataset_id      BIGINT          NOT NULL,
    eval_version    VARCHAR(50)     NOT NULL,
    hit             BOOLEAN         NOT NULL,
    rank            INT,
    actual_answer   TEXT,
    faithfulness    FLOAT,
    answer_relevancy FLOAT,
    eval_at         TIMESTAMP       NOT NULL DEFAULT NOW()
);
