CREATE TABLE GeographicZone
(
    id_geo_zone INT PRIMARY KEY,
    designation VARCHAR(100) NOT NULL
);
GO

CREATE TABLE Carrier
(
    carrier_id    INT PRIMARY KEY,
    name          VARCHAR(100)   NOT NULL
        CONSTRAINT uk_carrier_name UNIQUE,
    nif           VARCHAR(20)    NOT NULL
        CONSTRAINT uk_carrier_nif UNIQUE,
    phone         VARCHAR(20),
    cost_per_hour DECIMAL(10, 2) NOT NULL CHECK (cost_per_hour >= 0)
);
GO

CREATE TABLE Warehouse
(
    warehouse_id INT PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    address      VARCHAR(255) NOT NULL,
    latitude     DECIMAL(9, 6), -- WGS84
    longitude    DECIMAL(9, 6), -- WGS84
    id_geo_zone  INT          NOT NULL,
    FOREIGN KEY (id_geo_zone) REFERENCES GeographicZone (id_geo_zone)
);
GO

CREATE TABLE PhysicalZone
(
    physical_zone_id INT PRIMARY KEY,
    warehouse_id     INT            NOT NULL,
    designation      VARCHAR(50)    NOT NULL,
    capacity_volume  DECIMAL(10, 2) NOT NULL CHECK (capacity_volume > 0),
    FOREIGN KEY (warehouse_id) REFERENCES Warehouse (warehouse_id)
);
GO

CREATE TABLE Employee
(
    employee_id    INT PRIMARY KEY,
    citizen_card   VARCHAR(20)  NOT NULL
        CONSTRAINT uk_emp_cc UNIQUE,
    name           VARCHAR(100) NOT NULL,
    address        VARCHAR(255),
    tax_id         VARCHAR(20)  NOT NULL,
    monthly_salary DECIMAL(10, 2) CHECK (monthly_salary > 0),
    category       VARCHAR(50)  NOT NULL,
    birth_date     DATE         NOT NULL,
    warehouse_id   INT          NOT NULL,
    supervisor_id  INT,
    id_geo_zone    INT          NOT NULL,
    FOREIGN KEY (warehouse_id) REFERENCES Warehouse (warehouse_id),
    FOREIGN KEY (supervisor_id) REFERENCES Employee (employee_id),
    FOREIGN KEY (id_geo_zone) REFERENCES GeographicZone (id_geo_zone)
);
GO

CREATE TABLE Customer
(
    customer_id INT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    address     VARCHAR(255),
    zip_code    VARCHAR(20),
    mobile      VARCHAR(20),
    tax_id      VARCHAR(20),
    type_class  VARCHAR(50),
    id_geo_zone INT          NOT NULL,
    FOREIGN KEY (id_geo_zone) REFERENCES GeographicZone (id_geo_zone)
);
GO

CREATE TABLE Product
(
    product_ref        INT PRIMARY KEY,
    name               VARCHAR(100) NOT NULL,
    description        VARCHAR(255),
    purchase_price     DECIMAL(10, 2),
    current_sell_price DECIMAL(10, 2),
    unit_type          VARCHAR(20)
);
GO

CREATE TABLE PriceHistory
(
    history_id  INT PRIMARY KEY,
    product_ref INT            NOT NULL,
    sell_price  DECIMAL(10, 2) NOT NULL,
    start_date  DATE           NOT NULL,
    end_date    DATE,
    FOREIGN KEY (product_ref) REFERENCES Product (product_ref),
    CHECK (end_date IS NULL OR end_date >= start_date)
);
GO

CREATE TABLE WarehouseStockDefinition
(
    warehouse_id INT NOT NULL,
    product_ref  INT NOT NULL,
    min_stock    INT NOT NULL CHECK (min_stock >= 0),
    PRIMARY KEY (warehouse_id, product_ref),
    FOREIGN KEY (warehouse_id) REFERENCES Warehouse (warehouse_id),
    FOREIGN KEY (product_ref) REFERENCES Product (product_ref)
);
GO

CREATE TABLE Stock
(
    physical_zone_id INT NOT NULL,
    product_ref      INT NOT NULL,
    quantity         INT NOT NULL CHECK (quantity >= 0),
    PRIMARY KEY (physical_zone_id, product_ref),
    FOREIGN KEY (physical_zone_id) REFERENCES PhysicalZone (physical_zone_id),
    FOREIGN KEY (product_ref) REFERENCES Product (product_ref)
);
GO

CREATE TABLE SalesOrder
(
    order_id          INT PRIMARY KEY,
    registration_date DATE NOT NULL,
    customer_id       INT  NOT NULL,
    salesperson_id    INT  NOT NULL,
    status            VARCHAR(20) DEFAULT 'Pendente' CHECK (status IN ('Pendente', 'Processada', 'Cancelada')),
    FOREIGN KEY (customer_id) REFERENCES Customer (customer_id),
    FOREIGN KEY (salesperson_id) REFERENCES Employee (employee_id)
);
GO

CREATE TABLE SalesOrderLine
(
    order_id    INT NOT NULL,
    product_ref INT NOT NULL,
    quantity    INT NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (order_id, product_ref),
    FOREIGN KEY (order_id) REFERENCES SalesOrder (order_id),
    FOREIGN KEY (product_ref) REFERENCES Product (product_ref)
);
GO

CREATE TABLE DispatchNote
(
    dispatch_id      INT PRIMARY KEY,
    creation_date    DATE DEFAULT CAST(GETDATE() AS DATE),
    creation_time    TIME,
    resp_employee_id INT NOT NULL,
    order_id         INT NOT NULL,
    FOREIGN KEY (resp_employee_id) REFERENCES Employee (employee_id),
    FOREIGN KEY (order_id) REFERENCES SalesOrder (order_id)
);
GO

CREATE TABLE DispatchNoteLine
(
    dispatch_id      INT NOT NULL,
    product_ref      INT NOT NULL,
    physical_zone_id INT NOT NULL,
    quantity         INT NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (dispatch_id, product_ref, physical_zone_id),
    FOREIGN KEY (dispatch_id) REFERENCES DispatchNote (dispatch_id),
    FOREIGN KEY (physical_zone_id, product_ref) REFERENCES Stock (physical_zone_id, product_ref)
);
GO

CREATE TABLE Transport
(
    transport_id       INT PRIMARY KEY,
    carrier_id         INT      NOT NULL,
    dispatch_id        INT      NOT NULL,
    transport_datetime DATETIME NOT NULL,
    hours_used         DECIMAL(5, 2),
    FOREIGN KEY (carrier_id) REFERENCES Carrier (carrier_id),
    FOREIGN KEY (dispatch_id) REFERENCES DispatchNote (dispatch_id)
);
GO