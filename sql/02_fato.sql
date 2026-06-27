-- ##############################################################
-- #  DATA WAREHOUSE OLIST — 02: FATO (Supabase / PostgreSQL)
-- #
-- #  Monta dw.fato_vendas a partir do staging + dimensões (joins no banco).
-- #  Rode este arquivo DEPOIS do Hop (dims + staging carregados).
-- #  Idempotente: pode rodar quantas vezes quiser.
-- ##############################################################

-- Garante os índices de join no staging (acelera o INSERT abaixo)
CREATE INDEX IF NOT EXISTS idx_stg_order_items_order ON stg.order_items   (order_id);
CREATE INDEX IF NOT EXISTS idx_stg_orders_order      ON stg.orders        (order_id);
CREATE INDEX IF NOT EXISTS idx_stg_payments_order    ON stg.order_payments(order_id);
CREATE INDEX IF NOT EXISTS idx_stg_reviews_order     ON stg.order_reviews (order_id);

TRUNCATE dw.fato_vendas RESTART IDENTITY;

INSERT INTO dw.fato_vendas (
  sk_data_compra, sk_data_entrega, sk_cliente, sk_produto, sk_vendedor,
  sk_status_pedido, sk_pagamento, sk_geografia_cliente, sk_geografia_vendedor,
  nk_order_id, order_item_id, preco, valor_frete, valor_pagamento, qtd_parcelas,
  review_score, dias_entrega_estimado, dias_entrega_real, flag_entrega_atrasada
)
SELECT
  to_char(o.order_purchase_timestamp::timestamp,'YYYYMMDD')::int,
  CASE WHEN NULLIF(o.order_delivered_customer_date,'') IS NULL THEN -1
       ELSE to_char(o.order_delivered_customer_date::timestamp,'YYYYMMDD')::int END,
  COALESCE(dc.sk_cliente,  -1),
  COALESCE(dp.sk_produto,  -1),
  COALESCE(dv.sk_vendedor, -1),
  COALESCE(ds.sk_status_pedido, -1),
  COALESCE(dpg.sk_pagamento, -1),
  COALESCE(dgc.sk_geografia, -1),
  COALESCE(dgv.sk_geografia, -1),
  oi.order_id,
  oi.order_item_id::int,
  NULLIF(oi.price,'')::numeric,
  NULLIF(oi.freight_value,'')::numeric,
  CASE WHEN sp.soma_preco IS NULL OR sp.soma_preco = 0 THEN pay.valor_total
       ELSE round(pay.valor_total * (NULLIF(oi.price,'')::numeric / sp.soma_preco), 2) END,
  pay.qtd_parcelas,
  rv.review_score,
  CASE WHEN NULLIF(o.order_estimated_delivery_date,'') IS NULL THEN NULL
       ELSE (o.order_estimated_delivery_date::timestamp::date - o.order_purchase_timestamp::timestamp::date) END,
  CASE WHEN NULLIF(o.order_delivered_customer_date,'') IS NULL THEN NULL
       ELSE (o.order_delivered_customer_date::timestamp::date - o.order_purchase_timestamp::timestamp::date) END,
  CASE WHEN NULLIF(o.order_delivered_customer_date,'') IS NOT NULL
        AND o.order_delivered_customer_date::timestamp > o.order_estimated_delivery_date::timestamp
       THEN TRUE ELSE FALSE END
FROM stg.order_items oi
JOIN      stg.orders         o   ON o.order_id        = oi.order_id
LEFT JOIN dw.dim_cliente     dc  ON dc.nk_customer_id = o.customer_id
LEFT JOIN dw.dim_produto     dp  ON dp.nk_product_id  = oi.product_id
LEFT JOIN dw.dim_vendedor    dv  ON dv.nk_seller_id   = oi.seller_id
LEFT JOIN dw.dim_status_pedido ds ON ds.status_pedido = o.order_status
LEFT JOIN dw.dim_geografia   dgc ON dgc.zip_code_prefix = lpad(dc.customer_zip_code_prefix, 5, '0')
LEFT JOIN dw.dim_geografia   dgv ON dgv.zip_code_prefix = lpad(dv.seller_zip_code_prefix, 5, '0')
LEFT JOIN (
  SELECT order_id, SUM(NULLIF(price,'')::numeric) AS soma_preco
  FROM stg.order_items GROUP BY order_id
) sp ON sp.order_id = oi.order_id
LEFT JOIN (
  SELECT order_id,
         SUM(NULLIF(payment_value,'')::numeric)                                          AS valor_total,
         MAX(NULLIF(payment_installments,'')::int)                                       AS qtd_parcelas,
         (ARRAY_AGG(payment_type ORDER BY NULLIF(payment_value,'')::numeric DESC NULLS LAST))[1] AS tipo_pagamento
  FROM stg.order_payments GROUP BY order_id
) pay ON pay.order_id = oi.order_id
LEFT JOIN dw.dim_pagamento   dpg ON dpg.tipo_pagamento = pay.tipo_pagamento
LEFT JOIN (
  SELECT order_id, MAX(NULLIF(review_score,'')::int) AS review_score
  FROM stg.order_reviews GROUP BY order_id
) rv ON rv.order_id = oi.order_id;

-- Conferência final
SELECT 'dim_cliente' t, count(*) FROM dw.dim_cliente
UNION ALL SELECT 'dim_produto',  count(*) FROM dw.dim_produto
UNION ALL SELECT 'dim_vendedor', count(*) FROM dw.dim_vendedor
UNION ALL SELECT 'dim_geografia',count(*) FROM dw.dim_geografia
UNION ALL SELECT 'fato_vendas',  count(*) FROM dw.fato_vendas;
