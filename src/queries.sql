-- 2.1. Liste para cada armazém, todas as zonas fisicas onde atualmente se encontra o artigo mais encomendado.

SELECT w.name         AS WarehouseName,
       pz.designation AS PhysicalZoneDesignation
FROM Warehouse w
         JOIN
     PhysicalZone pz ON w.warehouse_id = pz.warehouse_id
         JOIN
     Stock s ON pz.physical_zone_id = s.physical_zone_id
WHERE s.product_ref = (
    -- Subquery to find the most ordered product
    SELECT TOP 1 product_ref
    FROM SalesOrderLine
    GROUP BY product_ref
    ORDER BY SUM(quantity) DESC)
  AND s.quantity > 0; -- Ensure the product is actually in stock in that zone
GO

-- 2.2. Liste o nome dos armazéns que têm em stock todos os artigos que existem no armazém que possui o maior número de empregados.

WITH WarehouseWithMostEmployees AS (
    -- 1. Encontrar o armazém com o maior número de funcionários
    SELECT TOP 1
        warehouse_id
    FROM
        Employee
    GROUP BY
        warehouse_id
    ORDER BY
        COUNT(employee_id) DESC
),
ProductsInMainWarehouse AS (
    -- 2. Obter todos os produtos distintos nesse armazém
    SELECT DISTINCT
        s.product_ref
    FROM
        Stock s
    JOIN
        PhysicalZone pz ON s.physical_zone_id = pz.physical_zone_id
    WHERE
        pz.warehouse_id = (SELECT warehouse_id FROM WarehouseWithMostEmployees) AND s.quantity > 0
)
-- 3. Encontrar os armazéns que têm todos os produtos da lista
SELECT
    w.name AS WarehouseName
FROM
    Warehouse w
JOIN
    PhysicalZone pz ON w.warehouse_id = pz.warehouse_id
JOIN
    Stock s ON pz.physical_zone_id = s.physical_zone_id
WHERE
    s.product_ref IN (SELECT product_ref FROM ProductsInMainWarehouse)
    AND w.warehouse_id != (SELECT warehouse_id FROM WarehouseWithMostEmployees) -- Excluir o próprio armazém principal
GROUP BY
    w.warehouse_id, w.name
HAVING
    COUNT(DISTINCT s.product_ref) = (SELECT COUNT(*) FROM ProductsInMainWarehouse);
GO

-- 2.3. Liste as zonas fisicas do armazém designado de XPTO, que possuem a maior quantidade de artigos em stock. 
-- No caso de a maior quantidade de artigos em stock for zero deverá aparecer uma mensagem com a seguinte indicação “ZONA FISICA SEM STOCK”.

DECLARE @MaxStock INT;

-- 1. Calcular o stock total por zona no armazém 'XPTO' e encontrar o máximo
SELECT @MaxStock = MAX(TotalQuantity)
FROM (
    SELECT 
        SUM(s.quantity) AS TotalQuantity
    FROM 
        PhysicalZone pz
    JOIN 
        Warehouse w ON pz.warehouse_id = w.warehouse_id
    LEFT JOIN 
        Stock s ON pz.physical_zone_id = s.physical_zone_id
    WHERE 
        w.name = 'XPTO'
    GROUP BY 
        pz.physical_zone_id
) AS ZoneStock;

-- 2. Verificar se o stock máximo é 0 e apresentar o resultado apropriado
IF @MaxStock > 0
BEGIN
    -- Se houver stock, listar as zonas com a quantidade máxima
    SELECT 
        pz.designation AS PhysicalZoneDesignation
    FROM 
        PhysicalZone pz
    JOIN 
        Warehouse w ON pz.warehouse_id = w.warehouse_id
    LEFT JOIN 
        Stock s ON pz.physical_zone_id = s.physical_zone_id
    WHERE 
        w.name = 'XPTO'
    GROUP BY 
        pz.physical_zone_id, pz.designation
    HAVING 
        SUM(ISNULL(s.quantity, 0)) = @MaxStock;
END
ELSE
BEGIN
    -- Se não houver stock, apresentar a mensagem
    SELECT 'ZONA FISICA SEM STOCK' AS Result;
END
GO

-- 2.4. Liste as zonas (nome da zona e código do armazém) que tenham todo o seu volume ocupado.
-- Nota: Assumindo que cada unidade de produto ocupa 1m³.

SELECT
    pz.designation AS ZoneName,
    pz.warehouse_id AS WarehouseCode
FROM
    PhysicalZone pz
JOIN
    Stock s ON pz.physical_zone_id = s.physical_zone_id
GROUP BY
    pz.physical_zone_id, pz.designation, pz.warehouse_id, pz.capacity_volume
HAVING
    SUM(s.quantity) = pz.capacity_volume
ORDER BY
    WarehouseCode ASC,
    ZoneName DESC;
GO

-- 2.5. Liste os armazéns que, no período de 01/03/2018 a 15/10/2018, têm o número total de encomendas pendentes, 
-- maior do que qualquer armazém da cidade do Porto.

WITH PortoMaxPending AS (
    -- 1. Encontrar o número máximo de encomendas pendentes em qualquer armazém do Porto
    SELECT 
        ISNULL(MAX(PendingCount), 0) AS MaxPending
    FROM (
        SELECT 
            COUNT(so.order_id) AS PendingCount
        FROM 
            SalesOrder so
        JOIN 
            Employee e ON so.salesperson_id = e.employee_id
        JOIN 
            Warehouse w ON e.warehouse_id = w.warehouse_id
        JOIN 
            GeographicZone gz ON w.id_geo_zone = gz.id_geo_zone
        WHERE 
            gz.designation = 'Porto'
            AND so.status = 'Pendente'
            AND so.registration_date BETWEEN '2018-03-01' AND '2018-10-15'
        GROUP BY 
            w.warehouse_id
    ) AS PortoCounts
),
AllWarehousePendingCounts AS (
    -- 2. Contar as encomendas pendentes para todos os armazéns no mesmo período
    SELECT 
        w.name AS WarehouseName,
        COUNT(so.order_id) AS PendingCount
    FROM 
        SalesOrder so
    JOIN 
        Employee e ON so.salesperson_id = e.employee_id
    JOIN 
        Warehouse w ON e.warehouse_id = w.warehouse_id
    WHERE 
        so.status = 'Pendente'
        AND so.registration_date BETWEEN '2018-03-01' AND '2018-10-15'
    GROUP BY 
        w.name
)
-- 3. Selecionar os armazéns cuja contagem é superior ao máximo do Porto
SELECT 
    awpc.WarehouseName
FROM 
    AllWarehousePendingCounts awpc, PortoMaxPending pmp
WHERE 
    awpc.PendingCount > pmp.MaxPending;
GO

-- 2.6. Liste os vendedores (número, nome e zona) que em 2015, registaram encomendas de artigos com valor superior a 1000€ 
-- e que nunca venderam o produto de nome “Produto espetacular.”

WITH SellersOfSpectacularProduct AS (
    -- 1. Encontrar todos os vendedores que já venderam o "Produto espetacular."
    SELECT DISTINCT
        so.salesperson_id
    FROM
        SalesOrder so
    JOIN
        SalesOrderLine sol ON so.order_id = sol.order_id
    JOIN
        Product p ON sol.product_ref = p.product_ref
    WHERE
        p.name = 'Produto espetacular.'
),
HighValueSellers2015 AS (
    -- 2. Encontrar vendedores que tiveram encomendas > 1000€ em 2015
    SELECT DISTINCT
        so.salesperson_id
    FROM
        SalesOrder so
    JOIN
        SalesOrderLine sol ON so.order_id = sol.order_id
    JOIN
        Product p ON sol.product_ref = p.product_ref
    WHERE
        YEAR(so.registration_date) = 2015
    GROUP BY
        so.order_id, so.salesperson_id
    HAVING
        SUM(sol.quantity * p.current_sell_price) > 1000
)
-- 3. Selecionar os vendedores que estão na segunda lista mas não na primeira
SELECT
    e.employee_id AS EmployeeNumber,
    e.name AS EmployeeName,
    gz.designation AS ZoneName
FROM
    Employee e
JOIN
    GeographicZone gz ON e.id_geo_zone = gz.id_geo_zone
WHERE
    e.employee_id IN (SELECT salesperson_id FROM HighValueSellers2015)
    AND e.employee_id NOT IN (SELECT salesperson_id FROM SellersOfSpectacularProduct);
GO

-- 2.7. Liste o produto e volume mensal encomendado, para o ano 2019, dos produtos que estão em armazéns 
-- cujo stock está pelo menos 50% acima do stock mínimo.

WITH OverstockedProducts AS (
    -- 1. Encontrar produtos cujo stock em algum armazém está 50% acima do mínimo
    SELECT DISTINCT
        wsd.product_ref
    FROM
        WarehouseStockDefinition wsd
    JOIN (
        -- Subquery para calcular o stock total de cada produto em cada armazém
        SELECT
            pz.warehouse_id,
            s.product_ref,
            SUM(s.quantity) AS TotalStock
        FROM
            Stock s
        JOIN
            PhysicalZone pz ON s.physical_zone_id = pz.physical_zone_id
        GROUP BY
            pz.warehouse_id, s.product_ref
    ) AS CurrentStock ON wsd.warehouse_id = CurrentStock.warehouse_id AND wsd.product_ref = CurrentStock.product_ref
    WHERE
        CurrentStock.TotalStock >= wsd.min_stock * 1.5
)
-- 2. Calcular o volume de vendas mensais para esses produtos em 2019
SELECT
    p.name AS ProductName,
    MONTH(so.registration_date) AS Month,
    SUM(sol.quantity) AS MonthlyVolume
FROM
    SalesOrder so
JOIN
    SalesOrderLine sol ON so.order_id = sol.order_id
JOIN
    Product p ON sol.product_ref = p.product_ref
WHERE
    YEAR(so.registration_date) = 2019
    AND sol.product_ref IN (SELECT product_ref FROM OverstockedProducts)
GROUP BY
    p.name,
    MONTH(so.registration_date)
ORDER BY
    ProductName,
    Month;
GO

-- 2.8. Liste o nome do empregado que não é supervisor e que efetuou notas de encomendas em maior número do que todos os supervisores 
-- que possuem um salário mensal entre 1000€ e 3000€.

WITH SupervisorsInSalaryRange AS (
    -- 1. Identificar os supervisores na faixa salarial especificada
    SELECT DISTINCT
        supervisor_id
    FROM
        Employee
    WHERE
        supervisor_id IS NOT NULL
        AND monthly_salary BETWEEN 1000 AND 3000
),
MaxSupervisorOrders AS (
    -- 2. Encontrar o número máximo de encomendas feitas por esse grupo de supervisores
    SELECT
        ISNULL(MAX(OrderCount), 0) AS MaxOrders
    FROM (
        SELECT
            COUNT(so.order_id) AS OrderCount
        FROM
            SalesOrder so
        WHERE
            so.salesperson_id IN (SELECT supervisor_id FROM SupervisorsInSalaryRange)
        GROUP BY
            so.salesperson_id
    ) AS SupervisorCounts
),
NonSupervisorOrders AS (
    -- 3. Contar as encomendas para cada empregado que não é supervisor
    SELECT
        e.employee_id,
        COUNT(so.order_id) AS OrderCount
    FROM
        Employee e
    LEFT JOIN
        SalesOrder so ON e.employee_id = so.salesperson_id
    WHERE
        e.employee_id NOT IN (SELECT DISTINCT supervisor_id FROM Employee WHERE supervisor_id IS NOT NULL)
    GROUP BY
        e.employee_id
)
-- 4. Encontrar os não-supervisores cuja contagem de encomendas excede o máximo dos supervisores
SELECT
    e.name
FROM
    Employee e
JOIN
    NonSupervisorOrders nso ON e.employee_id = nso.employee_id
WHERE
    nso.OrderCount > (SELECT MaxOrders FROM MaxSupervisorOrders);
GO

-- 2.9. Liste as guias de saída, entre o mês de Junho e Agosto de 2018, cuja hora de elaboração é inferior às 10 horas da manhã 
-- e com uma diferença entre a data da encomenda e a data da guia de saída superior a 10 dias.

SELECT
    dn.*
FROM
    DispatchNote dn
JOIN
    SalesOrder so ON dn.order_id = so.order_id
WHERE
    dn.creation_date BETWEEN '2018-06-01' AND '2018-08-31'
    AND DATEPART(hour, dn.creation_time) < 10
    AND DATEDIFF(day, so.registration_date, dn.creation_date) > 10;
GO
