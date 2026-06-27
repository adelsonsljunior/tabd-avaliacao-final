-- ##############################################################
-- #  DATA WAREHOUSE OLIST — 03: VIEWS DE BI (Supabase / PostgreSQL)
-- #
-- #  Camada de consumo para o Preset.io (Apache Superset).
-- #  Uma view por pergunta de negócio (ver README / docs/etapa3-bi.md).
-- #  Rode DEPOIS do 02_fato.sql. Idempotente (CREATE OR REPLACE).
-- #  No Preset, cada view vira um Dataset do schema `bi`.
-- ##############################################################

CREATE SCHEMA IF NOT EXISTS bi;

-- ============================================================
-- Pergunta 1 — Qual a receita total por categoria de produto?
-- ============================================================
CREATE OR REPLACE VIEW bi.vw_receita_categoria AS
SELECT
    dp.category_name                  AS categoria,
    COUNT(*)                          AS itens_vendidos,
    COUNT(DISTINCT f.nk_order_id)     AS pedidos,
    ROUND(SUM(f.preco), 2)            AS receita_total,
    ROUND(AVG(f.preco), 2)            AS ticket_medio_item
FROM dw.fato_vendas f
JOIN dw.dim_produto dp ON dp.sk_produto = f.sk_produto
WHERE f.sk_produto <> -1
GROUP BY dp.category_name
ORDER BY receita_total DESC;

-- ============================================================
-- Pergunta 2 — Quais estados têm maior volume de pedidos e
--              maior frete médio?
-- ============================================================
CREATE OR REPLACE VIEW bi.vw_estado_pedidos_frete AS
SELECT
    dc.customer_state                 AS estado,
    COUNT(DISTINCT f.nk_order_id)     AS qtd_pedidos,
    COUNT(*)                          AS qtd_itens,
    ROUND(SUM(f.preco), 2)            AS receita_total,
    ROUND(AVG(f.valor_frete), 2)      AS frete_medio,
    ROUND(AVG(f.preco), 2)            AS ticket_medio_item
FROM dw.fato_vendas f
JOIN dw.dim_cliente dc ON dc.sk_cliente = f.sk_cliente
WHERE f.sk_cliente <> -1
GROUP BY dc.customer_state
ORDER BY qtd_pedidos DESC;

-- ============================================================
-- Pergunta 3 — Como evoluiu o volume de vendas ao longo do tempo?
-- ============================================================
CREATE OR REPLACE VIEW bi.vw_vendas_tempo AS
SELECT
    dd.ano,
    dd.mes,
    dd.nome_mes,
    MAKE_DATE(dd.ano, dd.mes, 1)      AS mes_referencia,   -- eixo temporal p/ o Preset
    COUNT(DISTINCT f.nk_order_id)     AS qtd_pedidos,
    COUNT(*)                          AS qtd_itens,
    ROUND(SUM(f.preco), 2)            AS receita_total,
    ROUND(AVG(f.preco), 2)            AS ticket_medio_item
FROM dw.fato_vendas f
JOIN dw.dim_data dd ON dd.sk_data = f.sk_data_compra
WHERE f.sk_data_compra <> -1
GROUP BY dd.ano, dd.mes, dd.nome_mes
ORDER BY dd.ano, dd.mes;

-- ============================================================
-- Pergunta 4 — Qual o desempenho de entrega (% de atrasos)
--              por vendedor / região?
-- (apenas itens efetivamente entregues)
-- ============================================================
CREATE OR REPLACE VIEW bi.vw_atraso_entrega AS
SELECT
    dv.seller_state                              AS estado_vendedor,
    dv.nk_seller_id                              AS vendedor,
    COUNT(*)                                     AS itens_entregues,
    SUM((f.flag_entrega_atrasada)::int)          AS itens_atrasados,
    ROUND(100.0 * AVG((f.flag_entrega_atrasada)::int), 2) AS pct_atraso,
    ROUND(AVG(f.dias_entrega_real), 1)           AS dias_entrega_medio,
    ROUND(AVG(f.dias_entrega_estimado), 1)       AS dias_estimado_medio
FROM dw.fato_vendas f
JOIN dw.dim_vendedor dv ON dv.sk_vendedor = f.sk_vendedor
WHERE f.sk_vendedor <> -1
  AND f.dias_entrega_real IS NOT NULL       -- só pedidos entregues
GROUP BY dv.seller_state, dv.nk_seller_id;

-- ============================================================
-- Pergunta 5 — Qual a relação entre nota de avaliação e
--              prazo de entrega?
-- ============================================================
CREATE OR REPLACE VIEW bi.vw_review_prazo AS
SELECT
    f.review_score                               AS nota,
    COUNT(*)                                     AS qtd_avaliacoes,
    ROUND(AVG(f.dias_entrega_real), 1)           AS dias_entrega_medio,
    ROUND(AVG(f.dias_entrega_estimado), 1)       AS dias_estimado_medio,
    ROUND(100.0 * AVG((f.flag_entrega_atrasada)::int), 2) AS pct_atraso
FROM dw.fato_vendas f
WHERE f.review_score IS NOT NULL
  AND f.dias_entrega_real IS NOT NULL           -- só pedidos entregues
GROUP BY f.review_score
ORDER BY f.review_score;

-- Conferência rápida (linhas por view)
SELECT 'vw_receita_categoria'    v, count(*) FROM bi.vw_receita_categoria
UNION ALL SELECT 'vw_estado_pedidos_frete', count(*) FROM bi.vw_estado_pedidos_frete
UNION ALL SELECT 'vw_vendas_tempo',         count(*) FROM bi.vw_vendas_tempo
UNION ALL SELECT 'vw_atraso_entrega',       count(*) FROM bi.vw_atraso_entrega
UNION ALL SELECT 'vw_review_prazo',         count(*) FROM bi.vw_review_prazo;
