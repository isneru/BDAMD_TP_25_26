-- 2.1. listar zonas com o produto mais vendido por armazem.

SELECT w.name         AS WarehouseName,
       pz.designation AS PhysicalZoneDesignation
FROM Warehouse w
         JOIN
     PhysicalZone pz ON w.warehouse_id = pz.warehouse_id
         JOIN
     Stock s ON pz.physical_zone_id = s.physical_zone_id
WHERE s.product_ref = (
    -- descobrir qual o produto que sai mais
    SELECT TOP 1 product_ref
    FROM SalesOrderLine
    GROUP BY product_ref
    ORDER BY SUM(quantity) DESC)
  AND s.quantity > 0; -- garantir que existe stock real
GO

-- 2.2. armazens com stock igual ao do armazem com mais gente.

WITH WarehouseWithMostEmployees AS (
    -- 1. ver qual o armazem com mais empregados
    SELECT TOP 1 warehouse_id
    FROM Employee
    GROUP BY warehouse_id
    ORDER BY COUNT(employee_id) DESC),
     ProductsInMainWarehouse AS (
         -- 2. sacar a lista de produtos desse armazem
         SELECT DISTINCT s.product_ref
         FROM Stock s
                  JOIN
              PhysicalZone pz ON s.physical_zone_id = pz.physical_zone_id
         WHERE pz.warehouse_id = (SELECT warehouse_id FROM WarehouseWithMostEmployees)
           AND s.quantity > 0)
-- 3. ver quem tem tudo igual
SELECT w.name AS WarehouseName
FROM Warehouse w
         JOIN
     PhysicalZone pz ON w.warehouse_id = pz.warehouse_id
         JOIN
     Stock s ON pz.physical_zone_id = s.physical_zone_id
WHERE s.product_ref IN (SELECT product_ref FROM ProductsInMainWarehouse)
  AND w.warehouse_id != (SELECT warehouse_id FROM WarehouseWithMostEmployees) -- tirar o proprio armazem da lista
GROUP BY w.warehouse_id, w.name
HAVING COUNT(DISTINCT s.product_ref) = (SELECT COUNT(*) FROM ProductsInMainWarehouse);
GO

-- 2.3. zonas com mais stock no xpto (ou msg de erro se zero).

DECLARE @MaxStock INT;

-- 1. ver maximo de stock no xpto
SELECT @MaxStock = MAX(TotalQuantity)
FROM (SELECT SUM(s.quantity) AS TotalQuantity
      FROM PhysicalZone pz
               JOIN
           Warehouse w ON pz.warehouse_id = w.warehouse_id
               LEFT JOIN
           Stock s ON pz.physical_zone_id = s.physical_zone_id
      WHERE w.name = 'XPTO'
      GROUP BY pz.physical_zone_id) AS ZoneStock;

-- 2. validar se esta a zero e mostrar resultado
IF @MaxStock > 0
    BEGIN
        -- mostra as zonas se houver stock
        SELECT pz.designation AS PhysicalZoneDesignation
        FROM PhysicalZone pz
                 JOIN
             Warehouse w ON pz.warehouse_id = w.warehouse_id
                 LEFT JOIN
             Stock s ON pz.physical_zone_id = s.physical_zone_id
        WHERE w.name = 'XPTO'
        GROUP BY pz.physical_zone_id, pz.designation
        HAVING SUM(ISNULL(s.quantity, 0)) = @MaxStock;
    END
ELSE
    BEGIN
        -- avisa se nao houver nada
        SELECT 'ZONA FISICA SEM STOCK' AS Result;
    END
GO

-- 2.4. zonas com stock cheio

SELECT pz.designation  AS ZoneName,
       pz.warehouse_id AS WarehouseCode
FROM PhysicalZone pz
         JOIN
     Stock s ON pz.physical_zone_id = s.physical_zone_id
GROUP BY pz.physical_zone_id, pz.designation, pz.warehouse_id, pz.capacity_volume
HAVING SUM(s.quantity) = pz.capacity_volume
ORDER BY ZoneName DESC;
GO

-- 2.5. armazens com mais encomendas pendentes que o pior caso do porto (março-outubro 2018).
WITH PortoMaxPending AS (
    -- 1. ver o maximo de pendentes no porto
    SELECT ISNULL(MAX(PendingCount), 0) AS MaxPending
    FROM (SELECT COUNT(so.order_id) AS PendingCount
          FROM SalesOrder so
                   JOIN
               Employee e ON so.salesperson_id = e.employee_id
                   JOIN
               Warehouse w ON e.warehouse_id = w.warehouse_id
                   JOIN
               GeographicZone gz ON w.id_geo_zone = gz.id_geo_zone
          WHERE gz.designation = 'Porto'
            AND so.status = 'Pendente'
            AND so.registration_date BETWEEN '2018-03-01' AND '2018-10-15'
          GROUP BY w.warehouse_id) AS PortoCounts),
     AllWarehousePendingCounts AS (
         -- 2. contar pendentes de toda a gente
         SELECT w.name             AS WarehouseName,
                COUNT(so.order_id) AS PendingCount
         FROM SalesOrder so
                  JOIN
              Employee e ON so.salesperson_id = e.employee_id
                  JOIN
              Warehouse w ON e.warehouse_id = w.warehouse_id
         WHERE so.status = 'Pendente'
           AND so.registration_date BETWEEN '2018-03-01' AND '2018-10-15'
         GROUP BY w.name)
-- 3. filtrar quem esta pior que o porto
SELECT awpc.WarehouseName
FROM AllWarehousePendingCounts awpc,
     PortoMaxPending pmp
WHERE awpc.PendingCount > pmp.MaxPending;
GO

-- 2.6. vendedores top (>1000€ em 2015) que nunca venderam o "produto espetacular".

WITH SellersOfSpectacularProduct AS (
    -- 1. quem ja vendeu o tal produto
    SELECT DISTINCT so.salesperson_id
    FROM SalesOrder so
             JOIN
         SalesOrderLine sol ON so.order_id = sol.order_id
             JOIN
         Product p ON sol.product_ref = p.product_ref
    WHERE p.name = 'Produto espetacular.'),
     HighValueSellers2015 AS (
         -- 2. quem faturou bem em 2015
         SELECT DISTINCT so.salesperson_id
         FROM SalesOrder so
                  JOIN
              SalesOrderLine sol ON so.order_id = sol.order_id
                  JOIN
              Product p ON sol.product_ref = p.product_ref
         WHERE YEAR(so.registration_date) = 2015
         GROUP BY so.order_id, so.salesperson_id
         HAVING SUM(sol.quantity * p.current_sell_price) > 1000)
-- 3. cruzar as listas (os bons que nao venderam o tal produto)
SELECT e.employee_id  AS EmployeeNumber,
       e.name         AS EmployeeName,
       gz.designation AS ZoneName
FROM Employee e
         JOIN
     GeographicZone gz ON e.id_geo_zone = gz.id_geo_zone
WHERE e.employee_id IN (SELECT salesperson_id FROM HighValueSellers2015)
  AND e.employee_id NOT IN (SELECT salesperson_id FROM SellersOfSpectacularProduct);
GO

-- 2.7. vendas mensais 2019 de produtos com excesso de stock (50% acima do min).

WITH OverstockedProducts AS (
    -- 1. ver produtos com muito stock
    SELECT DISTINCT wsd.product_ref
    FROM WarehouseStockDefinition wsd
             JOIN (
        -- conta stock total por armazem
        SELECT pz.warehouse_id,
               s.product_ref,
               SUM(s.quantity) AS TotalStock
        FROM Stock s
                 JOIN
             PhysicalZone pz ON s.physical_zone_id = pz.physical_zone_id
        GROUP BY pz.warehouse_id, s.product_ref) AS CurrentStock
                  ON wsd.warehouse_id = CurrentStock.warehouse_id AND wsd.product_ref = CurrentStock.product_ref
    WHERE CurrentStock.TotalStock >= wsd.min_stock * 1.5)
-- 2. ver como foram as vendas disto em 2019
SELECT p.name                      AS ProductName,
       MONTH(so.registration_date) AS Month,
       SUM(sol.quantity)           AS MonthlyVolume
FROM SalesOrder so
         JOIN
     SalesOrderLine sol ON so.order_id = sol.order_id
         JOIN
     Product p ON sol.product_ref = p.product_ref
WHERE YEAR(so.registration_date) = 2019
  AND sol.product_ref IN (SELECT product_ref FROM OverstockedProducts)
GROUP BY p.name,
         MONTH(so.registration_date)
ORDER BY ProductName,
         Month;
GO

-- 2.8. empregados normais que vendem mais que supervisores (que ganham 1-3k).

WITH SupervisorsInSalaryRange AS (
    -- 1. apanhar supervisores nessa faixa salarial
    SELECT DISTINCT supervisor_id
    FROM Employee
    WHERE supervisor_id IS NOT NULL
      AND monthly_salary BETWEEN 1000 AND 3000),
     MaxSupervisorOrders AS (
         -- 2. ver qual o recorde de vendas deles
         SELECT ISNULL(MAX(OrderCount), 0) AS MaxOrders
         FROM (SELECT COUNT(so.order_id) AS OrderCount
               FROM SalesOrder so
               WHERE so.salesperson_id IN (SELECT supervisor_id FROM SupervisorsInSalaryRange)
               GROUP BY so.salesperson_id) AS SupervisorCounts),
     NonSupervisorOrders AS (
         -- 3. contar vendas da malta sem cargo
         SELECT e.employee_id,
                COUNT(so.order_id) AS OrderCount
         FROM Employee e
                  LEFT JOIN
              SalesOrder so ON e.employee_id = so.salesperson_id
         WHERE e.employee_id NOT IN (SELECT DISTINCT supervisor_id FROM Employee WHERE supervisor_id IS NOT NULL)
         GROUP BY e.employee_id)
-- 4. mostrar quem superou o recorde dos chefes
SELECT e.name
FROM Employee e
         JOIN
     NonSupervisorOrders nso ON e.employee_id = nso.employee_id
WHERE nso.OrderCount > (SELECT MaxOrders FROM MaxSupervisorOrders);
GO

-- 2.9. guias feitas antes das 10h e com delay > 10 dias (jun-ago 2018).

SELECT dn.*
FROM DispatchNote dn
         JOIN
     SalesOrder so ON dn.order_id = so.order_id
WHERE dn.creation_date BETWEEN '2018-06-01' AND '2018-08-31'
  AND DATEPART(hour, dn.creation_time) < 10
  AND DATEDIFF(day, so.registration_date, dn.creation_date) > 10;
GO


-- 3.1: quem trabalha mais no maior armazem
/*
    mostra nome e total de encomendas de quem nao é chefe
    no armazem com mais empregados.
*/
SELECT e.name                                                                       AS EmployeeName,
       w.name                                                                       AS WarehouseName,
       (SELECT COUNT(*) FROM SalesOrder so WHERE so.salesperson_id = e.employee_id) AS TotalOrders
FROM Employee e
         JOIN
     Warehouse w ON e.warehouse_id = w.warehouse_id
WHERE e.warehouse_id = (
    -- ver qual e o maior armazem
    SELECT TOP 1 warehouse_id
    FROM Employee
    GROUP BY warehouse_id
    ORDER BY COUNT(*) DESC)
  AND e.employee_id NOT IN
      (SELECT DISTINCT supervisor_id FROM Employee WHERE supervisor_id IS NOT NULL) -- ignorar chefias
ORDER BY TotalOrders DESC;
GO

-- 3.2: vendedores que dao lucro no armazem principal
/*
    cruzamos produtividade com lucro > 500e.
    so vendedores normais que trabalham no armazem com mais gente.
*/
WITH SaleProfit AS (SELECT so.salesperson_id,
                           p.name                                                   AS ProductName,
                           (p.current_sell_price - p.purchase_price) * sol.quantity AS Profit
                    FROM SalesOrder so
                             JOIN SalesOrderLine sol ON so.order_id = sol.order_id
                             JOIN Product p ON sol.product_ref = p.product_ref)
/* 2. juntar tudo */
SELECT e.name                                                                       AS EmployeeName,
       w.name                                                                       AS WarehouseName,
       sp.ProductName,
       sp.Profit,
       -- total de ordens deste gajo
       (SELECT COUNT(*) FROM SalesOrder so WHERE so.salesperson_id = e.employee_id) AS TotalOrders
FROM Employee e
         JOIN Warehouse w ON e.warehouse_id = w.warehouse_id
         JOIN SaleProfit sp ON e.employee_id = sp.salesperson_id
WHERE
  -- filtro do maior armazem
    e.warehouse_id = (SELECT TOP 1 warehouse_id
                      FROM Employee
                      GROUP BY warehouse_id
                      ORDER BY COUNT(*) DESC)
  -- sem chefes
  AND e.employee_id NOT IN (SELECT DISTINCT supervisor_id FROM Employee WHERE supervisor_id IS NOT NULL)
  -- so vendedores
  AND e.category = 'Vendedor'
  -- lucro > 500
  AND sp.Profit > 500

/* 3. order by no fim */
ORDER BY e.name, sp.Profit DESC;
GO

-- 3.3: eficiencia da logistica (tempo medio para despachar guias)
/*
    calcula os dias que a malta da logistica demora a tratar das guias.
    so consideramos quem ja despachou mais que uma para nao falsear a media.
*/
WITH ProcessingTimes AS (
    -- calculo dos dias entre pedido e guia
    SELECT dn.resp_employee_id,
           DATEDIFF(day, so.registration_date, dn.creation_date) AS DaysToProcess
    FROM DispatchNote dn
             JOIN
         SalesOrder so ON dn.order_id = so.order_id)
SELECT e.name                     AS EmployeeName,
       AVG(pt.DaysToProcess)      AS AverageProcessingDays,
       COUNT(pt.resp_employee_id) AS TotalDispatches
FROM Employee e
         JOIN
     ProcessingTimes pt ON e.employee_id = pt.resp_employee_id
WHERE e.category IN ('Fiel de Armazem', 'Motorista') -- so fiel de armazem e motoristas
GROUP BY e.name
HAVING COUNT(pt.resp_employee_id) > 1 -- filtrar quem tem pouca amostra
GO