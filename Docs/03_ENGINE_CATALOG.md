# Engine / Domain Catalog

Names describe ownership boundaries, not necessarily threads or processes.

## Core
- State Kernel — identity, ownership, revisions, transactions, invariants, commits.
- Simulation Clock — authoritative simulation time/speed.
- Event Scheduler — due-event ordering.
- Job System — bounded asynchronous computation.
- Determinism/Random Streams — replayable ordering/randomness.

## Platform
- Persistence — incremental durable state/recovery.
- Diagnostics / Black Box — trace/root-cause evidence.
- Performance/Thermal Governor — budgets, sustained workload adaptation.
- Map/Rendering — Metal, spatial index, LOD, clustering, visual interpolation.
- Query/Read Models — indexed/paginated UI projections.
- Document Store — media/document bytes + integrity metadata.

## World
- Geography/Infrastructure — countries, regions, cities, airports, ports, roads.
- Currency/Time/Jurisdiction.
- Market & Demand — aggregate demand cells, prices, seasonality.
- Macro Economy — inflation, wages, FX, interest, energy/commodity drivers.

## Enterprise capabilities
- Organization/Holding
- Finance/Ledger
- Treasury/Banking
- Sales/Pricing
- Procurement
- Inventory/Warehousing
- Manufacturing/BOM/Recipe
- Logistics/Cargo
- HR/Payroll
- Facilities
- Maintenance/Reliability
- Quality
- Contracts
- Compliance/Tax
- R&D
- Warranty/Customer Service
- Marketing

## Industry extensions
Aviation, Maritime, Road Transport, Automotive, Dairy, Mobile Devices, Energy, Banking/Financial Services, Real Estate and future sectors.

Industry modules define sector-specific constraints/assets/products while reusing generic capabilities.

## Rule
If adding a future industry requires rewriting State Kernel, Finance, HR and Persistence simply to exist, the architecture has failed.
