/*
 =========================================
 THE PROBLEMS (Why do this in SQL instead of the BI Tool?)
 =========================================

 1. The "We'll just filter it in Power BI" Trap:
    People often ask, "Why are we filtering rows and dropping columns here? Can't we just hide the bad rows and extra columns in the BI tool later?" 
    Sure, you could. But human beings are lazy. If you leave the garbage rows (is_valid_record = FALSE) in the table, eventually some analyst is going to forget to click the filter box in their dashboard. When they forget, fake data leaks into an executive report, and it becomes your fault.

 2. Column Hoarding (Information Overload):
    If we give business users every single column—including the ingestion dates, batch IDs, and error reasons from the clean layer—they get confused. Business users don't care how the data was built. If you hand them a column called "batch_id", some junior analyst will try to sum it up in a bar chart and complain to you that the numbers look weird.
 */
--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE VIEW `mart.dim_warehouse` AS
SELECT
    warehouse_id,
    warehouse_name,
    region,
    timezone,
    capacity_units,
    active_flag
from
    clean.clean_warehouses
WHERE
    is_valid_record = TRUE

--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 THE SOLUTIONS (How we built this table)
 =========================================
 1. Upstream Lockout (Trusting the Database, Not the Dashboard):
    By hardcoding `WHERE is_valid_record = TRUE` right here in the SQL view, we physically block the BI tools from ever seeing the quarantined data. We do not trust the BI layer to do the filtering. We do it once, at the root, so nobody can ever mess it up downstream.
    
 2. How I Picked the Columns (The Drop-Down Rule):
    What determines which columns make the cut? The rule is simple: If a business person would put it in a drop-down menu, use it to filter a dashboard, or slice a pie chart, it stays. 
    I kept the pure descriptive stuff (IDs, Names, Regions, Countries, Status). I brutally cut all the backend engineering columns (batch IDs, record update times). We are handing them a perfectly clean list of Nouns.
 */

 