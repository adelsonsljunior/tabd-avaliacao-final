-- ##############################################################
-- #  DATA WAREHOUSE OLIST — 01: ESTRUTURA (Supabase / PostgreSQL)
-- #
-- #  Recria TODO o schema do zero (dropa e cria, vazio).
-- #  Rode este arquivo ANTES do Hop.
-- #  Sequência: 01_schema.sql  ->  Hop (dims + staging)  ->  02_fato.sql
-- ##############################################################

DROP SCHEMA IF EXISTS dw  CASCADE;
DROP SCHEMA IF EXISTS stg CASCADE;
CREATE SCHEMA dw;
CREATE SCHEMA stg;

-- ===================== DIMENSÕES =====================

-- dim_data (calendário) — SCD Tipo 0
CREATE TABLE dw.dim_data (
    sk_data          INTEGER      PRIMARY KEY,
    data_completa    DATE         NOT NULL,
    dia              INTEGER      NOT NULL,
    mes              INTEGER      NOT NULL,
    ano              INTEGER      NOT NULL,
    trimestre        INTEGER      NOT NULL,
    dia_semana       VARCHAR(20)  NOT NULL,
    nome_mes         VARCHAR(20)  NOT NULL,
    flag_fim_semana  BOOLEAN      NOT NULL DEFAULT FALSE
);
INSERT INTO dw.dim_data VALUES (-1, '1900-01-01', 1, 1, 1900, 1, 'N/A', 'N/A', FALSE);
INSERT INTO dw.dim_data
SELECT
    TO_CHAR(d,'YYYYMMDD')::INT, d,
    EXTRACT(DAY FROM d)::INT, EXTRACT(MONTH FROM d)::INT, EXTRACT(YEAR FROM d)::INT,
    EXTRACT(QUARTER FROM d)::INT,
    CASE EXTRACT(DOW FROM d) WHEN 0 THEN 'Domingo' WHEN 1 THEN 'Segunda-feira'
        WHEN 2 THEN 'Terça-feira' WHEN 3 THEN 'Quarta-feira' WHEN 4 THEN 'Quinta-feira'
        WHEN 5 THEN 'Sexta-feira' WHEN 6 THEN 'Sábado' END,
    CASE EXTRACT(MONTH FROM d) WHEN 1 THEN 'Janeiro' WHEN 2 THEN 'Fevereiro' WHEN 3 THEN 'Março'
        WHEN 4 THEN 'Abril' WHEN 5 THEN 'Maio' WHEN 6 THEN 'Junho' WHEN 7 THEN 'Julho'
        WHEN 8 THEN 'Agosto' WHEN 9 THEN 'Setembro' WHEN 10 THEN 'Outubro'
        WHEN 11 THEN 'Novembro' WHEN 12 THEN 'Dezembro' END,
    (EXTRACT(DOW FROM d) IN (0,6))
FROM generate_series('2016-01-01'::DATE, '2019-12-31'::DATE, '1 day') AS d;

-- dim_cliente — SCD Tipo 1  (carregada pelo Hop)
CREATE TABLE dw.dim_cliente (
    sk_cliente               SERIAL       PRIMARY KEY,
    nk_customer_id           VARCHAR(50)  NOT NULL UNIQUE,
    customer_unique_id       VARCHAR(50),
    customer_city            VARCHAR(100),
    customer_state           VARCHAR(2),
    customer_zip_code_prefix VARCHAR(10)
);
INSERT INTO dw.dim_cliente (sk_cliente, nk_customer_id, customer_unique_id, customer_city, customer_state, customer_zip_code_prefix)
VALUES (-1, 'N/A', 'N/A', 'N/A', 'NA', '00000');

-- dim_produto — SCD Tipo 1  (carregada pelo Hop)
CREATE TABLE dw.dim_produto (
    sk_produto                 SERIAL       PRIMARY KEY,
    nk_product_id              VARCHAR(50)  NOT NULL UNIQUE,
    category_name              VARCHAR(100),
    category_name_english      VARCHAR(100),
    product_name_length        INTEGER,
    product_description_length INTEGER,
    product_photos_qty         INTEGER,
    product_weight_g           INTEGER,
    product_length_cm          INTEGER,
    product_height_cm          INTEGER,
    product_width_cm           INTEGER
);
INSERT INTO dw.dim_produto (sk_produto, nk_product_id, category_name, category_name_english)
VALUES (-1, 'N/A', 'sem_categoria', 'unknown');

-- dim_vendedor — SCD Tipo 1  (carregada pelo Hop)
CREATE TABLE dw.dim_vendedor (
    sk_vendedor            SERIAL       PRIMARY KEY,
    nk_seller_id           VARCHAR(50)  NOT NULL UNIQUE,
    seller_city            VARCHAR(100),
    seller_state           VARCHAR(2),
    seller_zip_code_prefix VARCHAR(10)
);
INSERT INTO dw.dim_vendedor (sk_vendedor, nk_seller_id, seller_city, seller_state, seller_zip_code_prefix)
VALUES (-1, 'N/A', 'N/A', 'NA', '00000');

-- dim_geografia — SCD Tipo 0  (carregada pelo Hop, agregada por CEP)
CREATE TABLE dw.dim_geografia (
    sk_geografia    SERIAL          PRIMARY KEY,
    zip_code_prefix VARCHAR(10)     NOT NULL UNIQUE,
    city            VARCHAR(100),
    state           VARCHAR(2),
    latitude        DECIMAL(15,10),
    longitude       DECIMAL(15,10)
);
INSERT INTO dw.dim_geografia (sk_geografia, zip_code_prefix, city, state)
VALUES (-1, '00000', 'N/A', 'NA');

-- dim_status_pedido — SCD Tipo 0  (fixa)
CREATE TABLE dw.dim_status_pedido (
    sk_status_pedido SERIAL       PRIMARY KEY,
    status_pedido    VARCHAR(30)  NOT NULL UNIQUE,
    descricao_status VARCHAR(100)
);
INSERT INTO dw.dim_status_pedido (sk_status_pedido, status_pedido, descricao_status)
VALUES (-1, 'N/A', 'Não Aplicável');
INSERT INTO dw.dim_status_pedido (status_pedido, descricao_status) VALUES
    ('delivered','Entregue'), ('shipped','Enviado'), ('canceled','Cancelado'),
    ('unavailable','Indisponível'), ('invoiced','Faturado'), ('processing','Em Processamento'),
    ('created','Criado'), ('approved','Aprovado');

-- dim_pagamento — SCD Tipo 0  (fixa)
CREATE TABLE dw.dim_pagamento (
    sk_pagamento        SERIAL       PRIMARY KEY,
    tipo_pagamento      VARCHAR(30)  NOT NULL UNIQUE,
    descricao_pagamento VARCHAR(100)
);
INSERT INTO dw.dim_pagamento (sk_pagamento, tipo_pagamento, descricao_pagamento)
VALUES (-1, 'N/A', 'Não Aplicável');
INSERT INTO dw.dim_pagamento (tipo_pagamento, descricao_pagamento) VALUES
    ('credit_card','Cartão de Crédito'), ('boleto','Boleto Bancário'),
    ('voucher','Voucher / Vale'), ('debit_card','Cartão de Débito'),
    ('not_defined','Não Definido');

-- ===================== TABELA FATO =====================
CREATE TABLE dw.fato_vendas (
    sk_venda              SERIAL         PRIMARY KEY,
    sk_data_compra        INTEGER        NOT NULL REFERENCES dw.dim_data(sk_data),
    sk_data_entrega       INTEGER                 REFERENCES dw.dim_data(sk_data),
    sk_cliente            INTEGER        NOT NULL REFERENCES dw.dim_cliente(sk_cliente),
    sk_produto            INTEGER        NOT NULL REFERENCES dw.dim_produto(sk_produto),
    sk_vendedor           INTEGER        NOT NULL REFERENCES dw.dim_vendedor(sk_vendedor),
    sk_status_pedido      INTEGER        NOT NULL REFERENCES dw.dim_status_pedido(sk_status_pedido),
    sk_pagamento          INTEGER        NOT NULL REFERENCES dw.dim_pagamento(sk_pagamento),
    sk_geografia_cliente  INTEGER                 REFERENCES dw.dim_geografia(sk_geografia),
    sk_geografia_vendedor INTEGER                 REFERENCES dw.dim_geografia(sk_geografia),
    nk_order_id           VARCHAR(50)    NOT NULL,
    order_item_id         INTEGER        NOT NULL,
    preco                 DECIMAL(10,2),
    valor_frete           DECIMAL(10,2),
    valor_pagamento       DECIMAL(10,2),
    qtd_parcelas          INTEGER,
    review_score          INTEGER,
    dias_entrega_estimado INTEGER,
    dias_entrega_real     INTEGER,
    flag_entrega_atrasada BOOLEAN,
    CONSTRAINT uq_fato_order_item UNIQUE (nk_order_id, order_item_id)
);
CREATE INDEX idx_fato_data_compra ON dw.fato_vendas (sk_data_compra);
CREATE INDEX idx_fato_cliente     ON dw.fato_vendas (sk_cliente);
CREATE INDEX idx_fato_produto     ON dw.fato_vendas (sk_produto);
CREATE INDEX idx_fato_vendedor    ON dw.fato_vendas (sk_vendedor);
CREATE INDEX idx_fato_status      ON dw.fato_vendas (sk_status_pedido);
CREATE INDEX idx_fato_pagamento   ON dw.fato_vendas (sk_pagamento);

-- ===================== STAGING (bruto, TEXT) =====================
CREATE TABLE stg.order_items (
  order_id TEXT, order_item_id TEXT, product_id TEXT, seller_id TEXT,
  shipping_limit_date TEXT, price TEXT, freight_value TEXT);
CREATE TABLE stg.orders (
  order_id TEXT, customer_id TEXT, order_status TEXT,
  order_purchase_timestamp TEXT, order_approved_at TEXT,
  order_delivered_carrier_date TEXT, order_delivered_customer_date TEXT,
  order_estimated_delivery_date TEXT);
CREATE TABLE stg.order_payments (
  order_id TEXT, payment_sequential TEXT, payment_type TEXT,
  payment_installments TEXT, payment_value TEXT);
CREATE TABLE stg.order_reviews (
  review_id TEXT, order_id TEXT, review_score TEXT, review_comment_title TEXT,
  review_comment_message TEXT, review_creation_date TEXT, review_answer_timestamp TEXT);

-- Índices de join (aceleram o INSERT do 02_fato.sql; o TRUNCATE do Hop os preserva)
CREATE INDEX idx_stg_order_items_order ON stg.order_items   (order_id);
CREATE INDEX idx_stg_orders_order      ON stg.orders        (order_id);
CREATE INDEX idx_stg_payments_order    ON stg.order_payments(order_id);
CREATE INDEX idx_stg_reviews_order     ON stg.order_reviews (order_id);

-- Pronto. Agora rode o Hop:  docker compose run --rm hop-run
-- e depois o 02_fato.sql
