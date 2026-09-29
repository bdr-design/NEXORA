# Enterprise Capabilities & Industries

## Organization
`Holding -> Subsidiary -> Business Unit -> Facility`

## No closed company types
A company is composed from capabilities. Do not build a giant switch for airline/dairy/phone/car/etc.

Reusable capabilities include Finance, Treasury, HR, Payroll, Sales, Procurement, Inventory, Manufacturing, BOM/Recipe, Logistics, Facilities, Maintenance, Quality, Contracts, Compliance, Tax, R&D, Warranty, Service, Marketing and Pricing.

Examples:
- Car dealership = Procurement + Inventory + Showrooms + Sales + Finance + Warranty + Service.
- Dairy manufacturer = Procurement + Manufacturing + Recipe + Quality + Cold Storage + Inventory + Logistics + Sales.
- Phone manufacturer = Procurement + Components + Manufacturing + BOM + Assembly + Quality + Inventory + Distribution + Sales + Warranty + R&D.

Industry extensions define sector-specific products/equipment/constraints but reuse generic capabilities.

## Manufacturing
Generic concepts: Product, SKU, Variant, BOM/Recipe, ProductionLine, ProductionOrder, Batch, Yield, Scrap, Quality, Capacity and LeadTime.

## Market depth
Demand is aggregated into demand cells/segments rather than modeled as millions of always-active customer objects.
