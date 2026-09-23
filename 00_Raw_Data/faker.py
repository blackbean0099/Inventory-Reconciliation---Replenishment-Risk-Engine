import os
import json
import math
import random
from collections import defaultdict, deque
from datetime import datetime, timedelta, date

import numpy as np
import pandas as pd
from faker import Faker

# ============================================================
# GLOBAL CONFIG
# ============================================================
SEED = 101
np.random.seed(SEED)
random.seed(SEED)
Faker.seed(SEED)
fake = Faker()

START_DATE = datetime(2025, 1, 1)
END_DATE = datetime(2026, 6, 30, 23, 59, 59)
CALENDAR_DAYS = (END_DATE.date() - START_DATE.date()).days + 1
INGESTION_TIMESTAMP = END_DATE + timedelta(days=35, hours=3)
OUTPUT_DIR = "supply_chain_raw_data"
SKU_COUNT = 150

os.makedirs(OUTPUT_DIR, exist_ok=True)

CURRENCIES = ["USD", "EUR", "SGD", "AED"]
WAREHOUSE_SPECS = [
    ("WH-LKO-01", "Lucknow Hub", "UP", "Asia/Kolkata", 50000),
    ("WH-DEL-02", "Delhi Central", "NCR", "Asia/Kolkata", 120000),
    ("WH-MUM-03", "Mumbai Dock", "MH", "Asia/Kolkata", 85000),
    ("WH-BLR-04", "Bangalore Tech", "KA", "Asia/Kolkata", 60000),
]
WAREHOUSES = [x[0] for x in WAREHOUSE_SPECS]

SUPPLIER_PROFILES = {
    "SUP-001": {"country": "China", "timezone": "Asia/Shanghai", "delay_mu": 0.5, "delay_sigma": 1.0, "short_ship_prob": 0.01, "cancel_prob": 0.01},
    "SUP-002": {"country": "Vietnam", "timezone": "Asia/Ho_Chi_Minh", "delay_mu": 2.0, "delay_sigma": 2.0, "short_ship_prob": 0.04, "cancel_prob": 0.02},
    "SUP-003": {"country": "USA", "timezone": "America/New_York", "delay_mu": 0.0, "delay_sigma": 0.8, "short_ship_prob": 0.02, "cancel_prob": 0.01},
    "SUP-004": {"country": "Taiwan", "timezone": "Asia/Taipei", "delay_mu": 4.0, "delay_sigma": 4.0, "short_ship_prob": 0.14, "cancel_prob": 0.04},
    "SUP-005": {"country": "Germany", "timezone": "Europe/Berlin", "delay_mu": 1.0, "delay_sigma": 1.5, "short_ship_prob": 0.03, "cancel_prob": 0.01},
    "SUP-006": {"country": "India", "timezone": "Asia/Kolkata", "delay_mu": 1.0, "delay_sigma": 1.0, "short_ship_prob": 0.03, "cancel_prob": 0.015},
    "SUP-007": {"country": "China", "timezone": "Asia/Shanghai", "delay_mu": 3.0, "delay_sigma": 5.0, "short_ship_prob": 0.08, "cancel_prob": 0.025},
    "SUP-008": {"country": "India", "timezone": "Asia/Kolkata", "delay_mu": 2.0, "delay_sigma": 2.5, "short_ship_prob": 0.06, "cancel_prob": 0.03},
}
SUPPLIERS = list(SUPPLIER_PROFILES.keys())

CARRIER_PROFILES = {
    "DHL Express": {"transit_mu": 2.0, "transit_sigma": 1.0, "customs_hold_prob": 0.02, "late_tail": 0.02},
    "FedEx": {"transit_mu": 3.0, "transit_sigma": 1.2, "customs_hold_prob": 0.03, "late_tail": 0.03},
    "Oceanic Freight": {"transit_mu": 9.0, "transit_sigma": 5.0, "customs_hold_prob": 0.20, "late_tail": 0.10},
    "Local-Post": {"transit_mu": 5.0, "transit_sigma": 4.0, "customs_hold_prob": 0.06, "late_tail": 0.08},
}
CARRIERS = list(CARRIER_PROFILES.keys())

CATEGORIES = ["Electronics", "Apparel", "Home", "Industrial"]
BRANDS = ["Brand-A", "Brand-B", "Brand-C", "Brand-D", "Brand-E"]
PACK_SIZES = ["1-Pack", "6-Pack", "12-Pack", "Case", "Pallet"]

# A few deliberately created demand shock windows.
DEMAND_SHOCKS = [
    (date(2025, 5, 10), date(2025, 5, 16), 1.80),
    (date(2025, 10, 1), date(2025, 10, 8), 1.60),
    (date(2026, 2, 8), date(2026, 2, 14), 2.10),
]

# ============================================================
# HELPERS: FX, DIRT, METADATA
# ============================================================
def daterange(start_date: date, end_date: date):
    for i in range((end_date - start_date).days + 1):
        yield start_date + timedelta(days=i)


def fx_truth():
    """Create a full deterministic internal FX curve used ONLY for simulation realism.
    The exported raw FX file intentionally has missing dates and formatting dirt.
    """
    start_rates = {"USD": 83.5, "EUR": 90.0, "SGD": 61.8, "AED": 22.7}
    rates = {}
    for d in daterange(START_DATE.date(), END_DATE.date()):
        for curr in CURRENCIES:
            if curr not in start_rates:
                continue
            if d == START_DATE.date():
                rates[(d, curr)] = start_rates[curr]
                continue
            prev = rates[(d - timedelta(days=1), curr)]
            drift = {"USD": 0.00005, "EUR": 0.00002, "SGD": -0.00001, "AED": 0.00000}[curr]
            shock = np.random.normal(drift, 0.0015)
            rates[(d, curr)] = round(prev * (1 + shock), 4)
    return rates


FX_TRUTH = fx_truth()


def maybe_dirty_token(value, probability=0.01):
    if random.random() >= probability:
        return value
    choices = ["", " ", "N/A", "UNKNOWN", "null", "NULL"]
    return random.choice(choices)


def corrupt_date(value):
    """Turn a datetime/date into one of several deliberately messy raw representations."""
    try:
        if pd.isna(value):
            return ""
    except (TypeError, ValueError):
        pass
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return ""
    if isinstance(value, pd.Timestamp):
        value = value.to_pydatetime()
    if isinstance(value, date) and not isinstance(value, datetime):
        value = datetime.combine(value, datetime.min.time())
    if not isinstance(value, datetime):
        return value

    r = random.random()
    if r < 0.005:
        return str((value - datetime(1899, 12, 30)).days)
    if r < 0.010:
        return str(int(value.timestamp()))
    if r < 0.020:
        return value.strftime("%d/%m/%Y")
    if r < 0.030:
        return value.strftime("%m-%d-%Y")
    if r < 0.040:
        return value.strftime("%Y-%m-%dT%H:%M:%SZ")
    if r < 0.050:
        return value.strftime("%Y-%m-%dT%H:%M:%S+05:30")
    return value.strftime("%Y-%m-%d %H:%M:%S")


def corrupt_currency_code(curr):
    r = random.random()
    if r < 0.005:
        return curr.lower()
    if r < 0.010:
        return f" {curr} "
    if r < 0.012:
        return "N/A"
    return curr


def corrupt_money(value, curr):
    if value is None:
        return ""
    r = random.random()
    if r < 0.01:
        return f" {value:,.2f} {curr} "
    if r < 0.02:
        return f"{value:,.2f}"
    if r < 0.025:
        return f"{value:.2f}".replace(".", ",")
    if r < 0.030:
        return "N/A"
    return f"{value:.2f}"


def dirty_id(value):
    if value is None:
        return ""
    r = random.random()
    if r < 0.005:
        return f" {value} "
    if r < 0.010:
        return value.lower()
    if r < 0.012:
        return "N/A"
    return value


def dirty_status(value):
    r = random.random()
    if r < 0.005:
        return value.lower()
    if r < 0.010:
        return f" {value} "
    return value


def dirty_name(value):
    if value is None:
        return ""
    r = random.random()
    if r < 0.02:
        return f" {value.lower()} "
    if r < 0.03:
        return value.replace(" ", "  ")
    if r < 0.035:
        return value.upper()
    return value


def add_metadata(df: pd.DataFrame, source_system: str, event_col: str, table_name: str) -> pd.DataFrame:
    out = df.copy()
    event_values = out[event_col].tolist() if event_col in out.columns else [START_DATE] * len(out)

    record_updates = []
    for v in event_values:
        if isinstance(v, pd.Timestamp):
            v = v.to_pydatetime()
        if isinstance(v, date) and not isinstance(v, datetime):
            v = datetime.combine(v, datetime.min.time())
        if not isinstance(v, datetime):
            v = START_DATE
        r = random.random()
        delay = 0 if r < 0.95 else (random.randint(1, 5) if r < 0.99 else random.randint(10, 30))
        updated = min(v + timedelta(days=delay, minutes=random.randint(0, 180)), INGESTION_TIMESTAMP - timedelta(minutes=1))
        record_updates.append(updated)

    out["source_system"] = source_system
    out["record_updated_at"] = record_updates
    out["ingestion_timestamp"] = INGESTION_TIMESTAMP
    batch_values = []
    for v in event_values:
        if isinstance(v, pd.Timestamp):
            v = v.to_pydatetime()
        if isinstance(v, date) and not isinstance(v, datetime):
            v = datetime.combine(v, datetime.min.time())
        batch_dt = v if isinstance(v, datetime) else START_DATE
        batch_values.append(f"BATCH_{batch_dt.strftime('%Y%m')}_{table_name.upper()}")
    out["batch_id"] = batch_values

    business_cols = [c for c in out.columns if c not in {"source_system", "record_updated_at", "ingestion_timestamp", "batch_id"}]
    return out, business_cols


def corrupt_business_columns(df: pd.DataFrame, business_cols, money_map=None, date_cols=None, id_cols=None, status_cols=None, nullable_cols=None, name_cols=None):
    out = df.copy()
    money_map = money_map or {}
    date_cols = date_cols or set()
    id_cols = id_cols or set()
    status_cols = status_cols or set()
    nullable_cols = nullable_cols or set()
    name_cols = name_cols or set()

    for col in business_cols:
        if col in date_cols:
            out[col] = out[col].apply(corrupt_date)
        elif col in money_map:
            currency_source = money_map[col]
            if isinstance(currency_source, str) and currency_source in out.columns:
                currency_values = out[currency_source].tolist()
            else:
                currency_values = list(currency_source)
            out[col] = [corrupt_money(v, c) for v, c in zip(out[col], currency_values)]
        elif col in id_cols:
            out[col] = out[col].apply(dirty_id)
        elif col in status_cols:
            out[col] = out[col].apply(dirty_status)
        elif col in name_cols:
            out[col] = out[col].apply(dirty_name)
        else:
            out[col] = out[col].apply(lambda x: maybe_dirty_token(x) if col in nullable_cols else x)

    out = out.astype({c: str for c in business_cols})
    out.rename(columns={c: f"{c}_raw" for c in business_cols}, inplace=True)
    return out


# ============================================================
# MASTER DATA TRUTH
# ============================================================
print("1/7  Creating master data truth...")

warehouse_rows = []
for wid, name, region, tz, capacity in WAREHOUSE_SPECS:
    warehouse_rows.append({
        "warehouse_id": wid,
        "warehouse_name": name,
        "region": region,
        "timezone": tz,
        "capacity_units": capacity,
        "active_flag": True,
    })
df_wh_truth = pd.DataFrame(warehouse_rows)

supplier_rows = []
for sid, prof in SUPPLIER_PROFILES.items():
    # Faker is used for synthetic names only. IDs remain deterministic.
    generated_name = fake.company().replace(",", "") + " Manufacturing"
    supplier_rows.append({
        "supplier_id": sid,
        "supplier_name": generated_name,
        "country": prof["country"],
        "timezone": prof["timezone"],
        "status": "ACTIVE",
    })
df_sup_truth = pd.DataFrame(supplier_rows)

skus = [f"SKU-{i:04d}" for i in range(1, SKU_COUNT + 1)]
pareto_samples = np.random.pareto(1.35, size=SKU_COUNT) + 1
pareto_weights = pareto_samples / pareto_samples.sum()

sku_profiles = {}
for i, sku in enumerate(skus):
    volatility = np.random.choice(["X", "Y", "Z"], p=[0.50, 0.32, 0.18])
    trend = np.random.uniform(-0.0003, 0.0008)
    discontinued_date = None
    if random.random() < 0.08:
        discontinued_date = START_DATE.date() + timedelta(days=random.randint(320, 450))
    sku_profiles[sku] = {
        "weight": float(pareto_weights[i]),
        "volatility": volatility,
        "base_cost": round(random.uniform(10, 150), 2),
        "cost_currency": random.choice(CURRENCIES),
        "category": random.choice(CATEGORIES),
        "brand": random.choice(BRANDS),
        "pack_size": random.choice(PACK_SIZES),
        "trend": trend,
        "primary_supplier": random.choice(SUPPLIERS),
        "discontinued_date": discontinued_date,
    }

# Valid supplier-policy truth: one or more historical versions per valid SKU-location.
policy_truth_rows = []
policy_lookup = {}
stocked_pairs = []

for sku in skus:
    prof = sku_profiles[sku]
    for wh in WAREHOUSES:
        # High-volume SKUs get broader warehouse coverage.
        coverage_prob = 0.92 if prof["weight"] >= np.quantile(pareto_weights, 0.8) else 0.78
        if random.random() > coverage_prob:
            continue
        stocked_pairs.append((wh, sku))

        sup = prof["primary_supplier"]
        if random.random() < 0.15:
            sup = random.choice(SUPPLIERS)
        curr = prof["cost_currency"]
        base_cost = prof["base_cost"]

        first_end = START_DATE + timedelta(days=random.randint(160, 240))
        versions = [
            {
                "supplier_id": sup, "sku_id": sku, "warehouse_id": wh,
                "lead_time_days": random.randint(7, 14),
                "moq": random.randint(80, 140),
                "reorder_point": random.randint(120, 220),
                "safety_stock": random.randint(40, 90),
                "unit_cost_foreign": base_cost,
                "currency_code": curr,
                "effective_from": START_DATE,
                "effective_to": first_end,
                "is_current": False,
            },
            {
                "supplier_id": sup, "sku_id": sku, "warehouse_id": wh,
                "lead_time_days": random.randint(9, 18),
                "moq": random.randint(120, 220),
                "reorder_point": random.randint(160, 300),
                "safety_stock": random.randint(60, 120),
                "unit_cost_foreign": round(base_cost * random.uniform(1.04, 1.15), 2),
                "currency_code": curr,
                "effective_from": first_end + timedelta(days=1),
                "effective_to": None,
                "is_current": True,
            },
        ]
        policy_lookup[(wh, sku)] = versions
        policy_truth_rows.extend(versions)

df_policy_truth = pd.DataFrame(policy_truth_rows)


def get_policy_truth(sku: str, wh: str, dt_value: datetime):
    versions = policy_lookup.get((wh, sku), [])
    for row in versions:
        end = row["effective_to"] or END_DATE
        if row["effective_from"] <= dt_value <= end:
            return row
    return None

# Product SCD truth. A subset changes classification/status historically.
product_truth_rows = []
for sku in skus:
    prof = sku_profiles[sku]
    changed = random.random() < 0.20
    if changed:
        change_date = START_DATE.date() + timedelta(days=random.randint(240, 420))
        product_truth_rows.append({
            "sku_id": sku,
            "category": prof["category"],
            "brand": prof["brand"],
            "pack_size": prof["pack_size"],
            "product_status": "ACTIVE",
            "effective_from": START_DATE,
            "effective_to": datetime.combine(change_date - timedelta(days=1), datetime.min.time()),
            "is_current": False,
        })
        new_category = random.choice([c for c in CATEGORIES if c != prof["category"]])
        product_truth_rows.append({
            "sku_id": sku,
            "category": new_category,
            "brand": prof["brand"],
            "pack_size": random.choice(PACK_SIZES),
            "product_status": "DISCONTINUED" if prof["discontinued_date"] else "ACTIVE",
            "effective_from": datetime.combine(change_date, datetime.min.time()),
            "effective_to": None,
            "is_current": True,
        })
    else:
        product_truth_rows.append({
            "sku_id": sku,
            "category": prof["category"],
            "brand": prof["brand"],
            "pack_size": prof["pack_size"],
            "product_status": "DISCONTINUED" if prof["discontinued_date"] else "ACTIVE",
            "effective_from": START_DATE,
            "effective_to": None,
            "is_current": True,
        })

df_product_truth = pd.DataFrame(product_truth_rows)

# ============================================================
# INVENTORY / PROCUREMENT STATE
# ============================================================
print("2/7  Initializing inventory and procurement state...")

inventory_on_hand = {}
reserved = defaultdict(int)
damaged = defaultdict(int)

for wh, sku in stocked_pairs:
    inventory_on_hand[(wh, sku)] = random.randint(180, 650)

open_pos = {}
arrival_calendar = defaultdict(list)
putaway_calendar = defaultdict(list)
pending_shipments = {}
backorders = deque()

sales_truth = {}
fulfillment_truth = []
movement_truth = []
snapshot_truth = []
po_truth = []
shipment_truth = []
telemetry_truth = []
receipt_truth = []

order_idx = po_idx = shipment_idx = receipt_idx = movement_idx = transfer_idx = 1

# Data structures for daily demand and later forecast evaluation.
daily_demand_truth = defaultdict(float)

# ============================================================
# DEMAND / INVENTORY HELPERS
# ============================================================
def demand_multiplier(sku: str, d: date):
    prof = sku_profiles[sku]
    m = 1.0 + prof["trend"] * max(0, (d - START_DATE.date()).days)
    if prof["volatility"] == "Y":
        m *= 1.0 + 0.30 * math.sin((d.timetuple().tm_yday / 365.25) * 2 * math.pi)
    elif prof["volatility"] == "Z":
        if random.random() < 0.72:
            return 0.0
        m *= random.uniform(0.7, 2.2)
    for s, e, factor in DEMAND_SHOCKS:
        if s <= d <= e:
            m *= factor
    if prof["discontinued_date"] and d >= prof["discontinued_date"]:
        return 0.0
    return max(0.0, m)


def available_qty(wh: str, sku: str):
    on_hand = inventory_on_hand.get((wh, sku), 0)
    return max(0, on_hand - reserved[(wh, sku)] - damaged[(wh, sku)])


def add_movement(when, sku, from_wh, to_wh, movement_type, qty, reference_id=None, transfer_id=None):
    global movement_idx
    movement_truth.append({
        "movement_id": f"MOV-{movement_idx:08d}",
        "movement_timestamp": when,
        "sku_id": sku,
        "from_warehouse_id": from_wh,
        "to_warehouse_id": to_wh,
        "movement_type": movement_type,
        "quantity": int(qty),
        "reference_id": reference_id or "",
        "transfer_id": transfer_id or "",
    })
    movement_idx += 1


# Opening balances are the true starting point.
for (wh, sku), qty in inventory_on_hand.items():
    add_movement(START_DATE, sku, "", wh, "OPENING_BALANCE", qty)

# ============================================================
# MAIN DISCRETE-EVENT LOOP
# ============================================================
print("3/7  Running 18-month event simulation...")

for day_offset in range(CALENDAR_DAYS):
    day = START_DATE.date() + timedelta(days=day_offset)
    current_day = datetime.combine(day, datetime.min.time())

    # --------------------------------------------------------
    # A. COMPLETE PUTAWAYS THAT BECAME AVAILABLE TODAY
    # --------------------------------------------------------
    for po_id in list(putaway_calendar.get(day, [])):
        po = open_pos.get(po_id)
        if not po:
            continue
        p = po["putaway"]
        wh, sku = po["warehouse_id"], po["sku_id"]
        inventory_on_hand[(wh, sku)] += p["received_qty"]
        add_movement(p["putaway_date"], sku, "VENDOR", wh, "RECEIPT", p["received_qty"], reference_id=po_id)
        po["putaway_completed"] = True
        po["received_qty"] = p["received_qty"]
        po["rejected_qty"] = p["rejected_qty"]

    # --------------------------------------------------------
    # B. APPLY DAMAGE EVENTS
    # --------------------------------------------------------
    for wh, sku in list(inventory_on_hand.keys()):
        if inventory_on_hand[(wh, sku)] <= 0:
            continue
        if random.random() < 0.004:
            damage_qty = max(1, int(np.random.poisson(2)))
            damage_qty = min(damage_qty, inventory_on_hand[(wh, sku)])
            inventory_on_hand[(wh, sku)] -= damage_qty
            damaged[(wh, sku)] = max(0, damaged[(wh, sku)] - damage_qty // 2)
            add_movement(current_day + timedelta(hours=4), sku, wh, "WASTE", "DAMAGE", -damage_qty, reference_id=f"DMG-{day}-{sku}")

    # --------------------------------------------------------
    # C. PROCESS BACKORDERS FIRST
    # --------------------------------------------------------
    new_backorders = deque()
    while backorders:
        bo = backorders.popleft()
        if bo["expiry_date"] < day:
            sales_truth[bo["order_id"]]["status"] = "CANCELLED"
            sales_truth[bo["order_id"]]["cancel_reason"] = "OUT_OF_STOCK"
            fulfillment_truth.append({
                "order_id": bo["order_id"], "order_line": 1,
                "event_timestamp": current_day + timedelta(hours=22),
                "warehouse_id": bo["warehouse_id"], "event_type": "CANCELLED", "qty": bo["remaining_qty"]
            })
            continue

        remaining = bo["remaining_qty"]
        wh = bo["warehouse_id"]
        sku = bo["sku_id"]
        avail = available_qty(wh, sku)
        if avail > 0:
            take = min(avail, remaining)
            inventory_on_hand[(wh, sku)] -= take
            reserved[(wh, sku)] = max(0, reserved[(wh, sku)] - take)
            sales_truth[bo["order_id"]]["fulfilled_qty"] += take
            fulfillment_truth.extend([
                {"order_id": bo["order_id"], "order_line": 1, "event_timestamp": current_day + timedelta(hours=9), "warehouse_id": wh, "event_type": "ALLOCATED", "qty": take},
                {"order_id": bo["order_id"], "order_line": 1, "event_timestamp": current_day + timedelta(hours=12), "warehouse_id": wh, "event_type": "SHIPPED", "qty": take},
            ])
            add_movement(current_day + timedelta(hours=12), sku, wh, "CUSTOMER", "SALE", -take, reference_id=bo["order_id"])
            remaining -= take

        if remaining > 0:
            new_backorders.append({**bo, "remaining_qty": remaining})
        else:
            sales_truth[bo["order_id"]]["status"] = "COMPLETED"
            sales_truth[bo["order_id"]]["cancel_reason"] = ""
    backorders = new_backorders

    # --------------------------------------------------------
    # D. GENERATE CUSTOMER DEMAND
    # --------------------------------------------------------
    order_count = int(np.random.poisson(72))
    for _ in range(max(25, min(120, order_count))):
        sku = np.random.choice(skus, p=pareto_weights)
        prof = sku_profiles[sku]
        mult = demand_multiplier(sku, day)
        if mult == 0:
            continue

        qty_base = np.random.gamma(shape=2.0 if prof["volatility"] != "Z" else 1.5, scale=2.0)
        qty = max(1, int(round(qty_base * mult)))
        primary_wh = random.choice(WAREHOUSES)
        if (primary_wh, sku) not in inventory_on_hand:
            stocked = [w for w in WAREHOUSES if (w, sku) in inventory_on_hand]
            if not stocked:
                continue
            primary_wh = random.choice(stocked)

        order_dt = current_day + timedelta(hours=random.randint(7, 21), minutes=random.randint(0, 59))
        promised_dt = order_dt + timedelta(days=random.randint(2, 5))
        order_id = f"ORD-{order_idx:08d}"

        # Price independently from procurement currency.
        cost_curr = prof["cost_currency"]
        base_cost_inr = prof["base_cost"] * FX_TRUTH[(day, cost_curr)]
        sale_curr = random.choice(CURRENCIES)
        gross_unit_inr = base_cost_inr * random.uniform(1.20, 1.45)
        sale_price_foreign = gross_unit_inr / FX_TRUTH[(day, sale_curr)]
        discount_rate = random.uniform(0.00, 0.12) if random.random() < 0.35 else 0.0
        discount_foreign = sale_price_foreign * qty * discount_rate

        remaining = qty
        allocations = []
        # Primary warehouse first, then another warehouse for split fulfillment.
        candidate_whs = [primary_wh] + [w for w in WAREHOUSES if w != primary_wh and (w, sku) in inventory_on_hand]
        for wh in candidate_whs[:2]:
            avail = available_qty(wh, sku)
            if avail <= 0 or remaining <= 0:
                continue
            take = min(avail, remaining)
            allocations.append((wh, take))
            remaining -= take

        fulfilled = sum(q for _, q in allocations)
        if fulfilled == qty:
            status = "COMPLETED"
            cancel_reason = ""
        elif fulfilled > 0:
            status = "PARTIAL"
            cancel_reason = ""
        else:
            status = "CANCELLED"
            cancel_reason = "OUT_OF_STOCK"

        sales_truth[order_id] = {
            "order_id": order_id,
            "order_line": 1,
            "order_timestamp": order_dt,
            "sku_id": sku,
            "warehouse_id": primary_wh if random.random() > 0.05 else "",
            "ordered_qty": qty,
            "fulfilled_qty": fulfilled,
            "unit_price_foreign": round(sale_price_foreign, 2),
            "discount_amount_foreign": round(discount_foreign, 2),
            "currency_code": sale_curr,
            "status": status,
            "cancel_reason": cancel_reason,
            "customer_promised_delivery_date": promised_dt,
        }

        for wh, take in allocations:
            # Allocate immediately; ship within the same day for most, next day for some.
            inventory_on_hand[(wh, sku)] -= take
            fulfillment_truth.append({
                "order_id": order_id, "order_line": 1,
                "event_timestamp": order_dt + timedelta(minutes=10),
                "warehouse_id": wh, "event_type": "ALLOCATED", "qty": take,
            })
            if random.random() < 0.10:
                fulfillment_truth.append({
                    "order_id": order_id, "order_line": 1,
                    "event_timestamp": order_dt + timedelta(days=1, hours=2),
                    "warehouse_id": wh, "event_type": "SHIPPED", "qty": take,
                })
            else:
                fulfillment_truth.append({
                    "order_id": order_id, "order_line": 1,
                    "event_timestamp": order_dt + timedelta(minutes=120),
                    "warehouse_id": wh, "event_type": "SHIPPED", "qty": take,
                })
            add_movement(order_dt + timedelta(hours=2), sku, wh, "CUSTOMER", "SALE", -take, reference_id=order_id)
            daily_demand_truth[(day, sku)] += take

        if remaining > 0 and status == "PARTIAL":
            # Backorder can be satisfied later or cancelled.
            backorders.append({
                "order_id": order_id,
                "sku_id": sku,
                "warehouse_id": primary_wh,
                "remaining_qty": remaining,
                "expiry_date": day + timedelta(days=random.randint(1, 3)),
            })
            reserved[(primary_wh, sku)] += min(remaining, max(0, available_qty(primary_wh, sku)))
            fulfillment_truth.append({
                "order_id": order_id, "order_line": 1,
                "event_timestamp": order_dt + timedelta(minutes=20),
                "warehouse_id": primary_wh, "event_type": "BACKORDERED", "qty": remaining,
            })

        order_idx += 1

    # --------------------------------------------------------
    # E. REPLENISHMENT: USE THE TRUE ACTIVE SCD POLICY
    # --------------------------------------------------------
    for wh, sku in list(inventory_on_hand.keys()):
        policy = get_policy_truth(sku, wh, current_day)
        if policy is None:
            continue
        if inventory_on_hand[(wh, sku)] > policy["reorder_point"]:
            continue
        key = (wh, sku)
        if any(p["status"] in {"OPEN", "SHIPPED", "PARTIALLY_RECEIVED"} for p in open_pos.values() if (p["warehouse_id"], p["sku_id"]) == key):
            continue

        supplier = policy["supplier_id"]
        s_prof = SUPPLIER_PROFILES[supplier]
        carrier = random.choice(CARRIERS)
        c_prof = CARRIER_PROFILES[carrier]
        po_qty = max(policy["moq"], int(round(policy["reorder_point"] * random.uniform(1.5, 2.3))))
        po_date = current_day + timedelta(hours=random.randint(8, 16))
        supplier_promise = po_date + timedelta(days=policy["lead_time_days"])
        supplier_delay = max(0, int(round(np.random.normal(s_prof["delay_mu"], s_prof["delay_sigma"]))))
        handover = supplier_promise + timedelta(days=supplier_delay)
        transit = max(1, int(round(np.random.normal(c_prof["transit_mu"], c_prof["transit_sigma"]))))
        expected_arrival = handover + timedelta(days=max(1, int(round(c_prof["transit_mu"]))))
        actual_arrival = handover + timedelta(days=transit)

        po_id = f"PO-{po_idx:08d}"
        ship_id = f"SHP-{shipment_idx:08d}"
        tracking_id = f"TRK-{random.randint(10000000, 99999999)}"
        cancel = random.random() < s_prof["cancel_prob"]
        has_shipment = not cancel and random.random() > 0.02

        po_truth.append({
            "po_id": po_id,
            "po_line": 1,
            "po_date": po_date,
            "supplier_id": supplier,
            "sku_id": sku,
            "warehouse_id": wh,
            "ordered_qty": po_qty,
            "unit_cost_foreign": policy["unit_cost_foreign"],
            "currency_code": policy["currency_code"],
            "expected_delivery_date": expected_arrival,
            "supplier_promised_ship_date": supplier_promise,
            "status": "CANCELLED" if cancel else ("SHIPPED" if has_shipment else "OPEN"),
        })

        open_pos[po_id] = {
            "po_id": po_id, "warehouse_id": wh, "sku_id": sku, "supplier_id": supplier,
            "ordered_qty": po_qty, "status": "CANCELLED" if cancel else ("SHIPPED" if has_shipment else "OPEN"),
            "actual_arrival": actual_arrival, "po_date": po_date,
            "supplier_handover": handover, "ship_id": ship_id, "tracking_id": tracking_id,
        }

        if has_shipment:
            inbound_shipments_row = {
                "shipment_id": ship_id,
                "po_id": po_id,
                "tracking_id": tracking_id,
                "carrier_id": carrier,
                "supplier_handover_date": handover,
                "ship_date": handover,
                "expected_arrival_date": expected_arrival,
                "destination_warehouse_id": wh,
            }
            shipment_truth.append(inbound_shipments_row)
            arrival_calendar[actual_arrival.date()].append(po_id)

            events = [
                {"epoch_time": int((po_date + timedelta(hours=1)).timestamp()), "event": "PO_CONFIRMED", "location": "Supplier ERP", "exception_code": "NONE"},
                {"epoch_time": int(handover.timestamp()), "event": "SUPPLIER_HANDOVER", "location": supplier, "exception_code": "NONE"},
            ]
            if random.random() < c_prof["customs_hold_prob"]:
                hold_time = handover + timedelta(days=max(1, int(transit * 0.3)))
                events.append({"epoch_time": int(hold_time.timestamp()), "event": "CUSTOMS_HOLD", "location": "Transshipment Hub", "exception_code": "CUSTOMS_HOLD"})
                events.append({"epoch_time": int((hold_time + timedelta(days=random.randint(1, 4))).timestamp()), "event": "CUSTOMS_CLEARED", "location": "Transshipment Hub", "exception_code": "NONE"})
            events.extend([
                {"epoch_time": int((actual_arrival - timedelta(hours=2)).timestamp()), "event": "DESTINATION_ARRIVAL", "location": wh, "exception_code": "NONE"},
                {"epoch_time": int(actual_arrival.timestamp()), "event": "DOCK_RECEIVED", "location": wh, "exception_code": "NONE"},
            ])
            telemetry_truth.append({
                "tracking_id": tracking_id,
                "shipment_id": ship_id,
                "carrier_payload": json.dumps({"status": "DELIVERED", "events": events}),
            })

        po_idx += 1
        shipment_idx += int(has_shipment)

    # --------------------------------------------------------
    # F. PROCESS ARRIVALS AT DOCK; INVENTORY ONLY AFTER PUTAWAY
    # --------------------------------------------------------
    for po_id in list(arrival_calendar.get(day, [])):
        po = open_pos.get(po_id)
        if not po or po["status"] != "SHIPPED":
            continue

        s_prof = SUPPLIER_PROFILES[po["supplier_id"]]
        short_ship = random.random() < s_prof["short_ship_prob"]
        shipped_qty = po["ordered_qty"]
        if short_ship:
            shipped_qty = max(1, int(round(po["ordered_qty"] * random.uniform(0.70, 0.95))))
        rejected_qty = int(shipped_qty * random.uniform(0.00, 0.04)) if random.random() < 0.10 else 0
        received_qty = max(0, shipped_qty - rejected_qty)
        actual_receipt = po["actual_arrival"]
        putaway_date = actual_receipt + timedelta(days=random.randint(1, 3), hours=random.randint(1, 5))

        putaway_calendar[putaway_date.date()].append(po_id)
        po["status"] = "PARTIALLY_RECEIVED" if received_qty < po["ordered_qty"] else "CLOSED"
        po["putaway"] = {"putaway_date": putaway_date, "received_qty": received_qty, "rejected_qty": rejected_qty}

        receipt_truth.append({
            "receipt_id": f"REC-{receipt_idx:08d}",
            "po_id": po_id,
            "sku_id": po["sku_id"],
            "warehouse_id": po["warehouse_id"],
            "actual_receipt_date": actual_receipt,
            "putaway_date": putaway_date,
            "received_qty": received_qty,
            "rejected_qty": rejected_qty,
            "wms_bin_location": f"{po['warehouse_id']}#ASL-{random.randint(1,9)}#SHF-{random.choice(['A','B','C'])}#BIN-{random.randint(10,99)}",
        })
        receipt_idx += 1

    # --------------------------------------------------------
    # G. INVENTORY TRANSFERS AND CYCLE COUNTS
    # --------------------------------------------------------
    if random.random() < 0.035:
        source = random.choice(WAREHOUSES)
        destination = random.choice([w for w in WAREHOUSES if w != source])
        candidates = [sku for sku in skus if (source, sku) in inventory_on_hand and (destination, sku) in inventory_on_hand]
        if candidates:
            sku = random.choice(candidates)
            qty = min(random.randint(20, 80), available_qty(source, sku))
            if qty > 0:
                transfer_id = f"TRF-{transfer_idx:08d}"
                inventory_on_hand[(source, sku)] -= qty
                inventory_on_hand[(destination, sku)] += qty
                # Truth has both sides.
                add_movement(current_day + timedelta(hours=15), sku, source, destination, "TRANSFER_OUT", -qty, reference_id=transfer_id, transfer_id=transfer_id)
                add_movement(current_day + timedelta(hours=15, minutes=20), sku, source, destination, "TRANSFER_IN", qty, reference_id=transfer_id, transfer_id=transfer_id)
                transfer_idx += 1

    if random.random() < 0.015:
        wh, sku = random.choice(stocked_pairs)
        adj = random.randint(-25, 25)
        # Keep physical reality non-negative.
        if inventory_on_hand[(wh, sku)] + adj >= 0:
            inventory_on_hand[(wh, sku)] += adj
            add_movement(current_day + timedelta(hours=18), sku, "", wh, "CYCLE_COUNT", adj, reference_id=f"CC-{day}-{sku}-{wh}")

    # --------------------------------------------------------
    # H. END-OF-DAY WMS SNAPSHOT
    # --------------------------------------------------------
    # WMS normally reports each active SKU-location, but skips some weekend batches.
    if not (day.weekday() >= 5 and random.random() < 0.20):
        for wh, sku in stocked_pairs:
            on_hand = inventory_on_hand[(wh, sku)]
            reserved_qty = min(max(0, reserved[(wh, sku)]), max(on_hand, 0))
            damaged_qty = min(max(0, damaged[(wh, sku)]), max(on_hand, 0))
            snapshot = {
                "snapshot_date": current_day,
                "warehouse_id": wh,
                "sku_id": sku,
                "on_hand_qty": on_hand,
                "reserved_qty": reserved_qty,
                "damaged_qty": damaged_qty,
                "source_timestamp": current_day + timedelta(hours=23, minutes=50),
            }
            r = random.random()
            if r < 0.02:
                snapshot["on_hand_qty"] += random.randint(20, 80)
            elif r < 0.04:
                snapshot["on_hand_qty"] -= random.randint(20, 80)
            snapshot_truth.append(snapshot)

# ============================================================
# BUILD DATAFRAMES FROM TRUTH
# ============================================================
print("4/7  Building source-system tables from truth...")

# Synchronize final PO state-machine status back to the source-system record.
final_po_status = {po_id: po.get("status", "OPEN") for po_id, po in open_pos.items()}
for row in po_truth:
    row["status"] = final_po_status.get(row["po_id"], row["status"])

df_sales_truth = pd.DataFrame(sales_truth.values())
df_fulfill_truth = pd.DataFrame(fulfillment_truth)
df_mov_truth = pd.DataFrame(movement_truth)
df_snap_truth = pd.DataFrame(snapshot_truth)
df_po_truth = pd.DataFrame(po_truth)
df_ship_truth = pd.DataFrame(shipment_truth)
df_telemetry_truth = pd.DataFrame(telemetry_truth)
df_receipt_truth = pd.DataFrame(receipt_truth)

# ------------------------------------------------------------
# Add deliberate raw-only anomalies without poisoning simulation truth.
# ------------------------------------------------------------
# Sales state conflicts: cancelled but fulfilled quantity > 0.
cancelled_ids = df_sales_truth.loc[df_sales_truth["status"] == "CANCELLED", "order_id"].tolist()
if cancelled_ids:
    conflict_ids = random.sample(cancelled_ids, min(max(1, int(len(cancelled_ids) * 0.02)), len(cancelled_ids)))
    df_sales_raw_base = df_sales_truth.copy()
    df_sales_raw_base.loc[df_sales_raw_base["order_id"].isin(conflict_ids), "fulfilled_qty"] = df_sales_raw_base.loc[df_sales_raw_base["order_id"].isin(conflict_ids), "ordered_qty"]
else:
    df_sales_raw_base = df_sales_truth.copy()

# Orphan receipts: clone legitimate receipts and point them to nonexistent POs.
df_receipt_raw_base = df_receipt_truth.copy()
if len(df_receipt_raw_base) >= 10:
    orphan_n = max(10, int(len(df_receipt_raw_base) * 0.01))
    orphan_idx = np.random.choice(df_receipt_raw_base.index, size=min(orphan_n, len(df_receipt_raw_base)), replace=False)
    df_receipt_raw_base.loc[orphan_idx, "po_id"] = "PO-ORPHAN-999999"

    # Timeline anomalies: receipt before PO date.
    po_date_map = df_po_truth.set_index("po_id")["po_date"].to_dict()
    timeline_idx = np.random.choice(df_receipt_raw_base.index, size=max(1, int(len(df_receipt_raw_base) * 0.015)), replace=False)
    for idx in timeline_idx:
        po = df_receipt_raw_base.loc[idx, "po_id"]
        base = po_date_map.get(po, START_DATE)
        df_receipt_raw_base.loc[idx, "actual_receipt_date"] = base - timedelta(days=random.randint(1, 3))

# Make raw movement table lose some transfer-IN observations, creating reconciliation failures.
df_mov_raw_base = df_mov_truth.copy()
transfer_in_idx = df_mov_raw_base.index[df_mov_raw_base["movement_type"] == "TRANSFER_IN"].tolist()
if transfer_in_idx:
    drop_n = max(1, int(len(transfer_in_idx) * 0.05))
    drop_idx = random.sample(transfer_in_idx, min(drop_n, len(transfer_in_idx)))
    df_mov_raw_base = df_mov_raw_base.drop(index=drop_idx).reset_index(drop=True)

# Product SCD raw is truth plus tiny overlap/current-flag corruption.
df_product_raw_base = df_product_truth.copy()
current_product = df_product_raw_base[df_product_raw_base["is_current"] == True]
if not current_product.empty:
    bad_prod = current_product.sample(frac=0.01, random_state=SEED)
    bad_rows = bad_prod.copy()
    bad_rows["effective_from"] = bad_rows["effective_from"] + timedelta(days=10)
    bad_rows["effective_to"] = None
    bad_rows["is_current"] = True
    df_product_raw_base = pd.concat([df_product_raw_base, bad_rows], ignore_index=True)

# Supplier-policy SCD raw is truth plus deliberate overlapping/current duplicates.
df_policy_raw_base = df_policy_truth.copy()
current_policy = df_policy_raw_base[df_policy_raw_base["is_current"] == True]
if not current_policy.empty:
    bad_policy = current_policy.sample(frac=0.01, random_state=SEED)
    overlap_rows = bad_policy.copy()
    overlap_rows["effective_from"] = overlap_rows["effective_from"] - pd.to_timedelta(np.random.randint(20, 80, size=len(overlap_rows)), unit="D")
    overlap_rows["effective_to"] = None
    overlap_rows["is_current"] = True
    overlap_rows["unit_cost_foreign"] = overlap_rows["unit_cost_foreign"] * 1.06
    df_policy_raw_base = pd.concat([df_policy_raw_base, overlap_rows], ignore_index=True)

# Add true duplicate sales rows with later record updates after metadata is attached.
# Snapshot duplicates are added later too, with conflicting on_hand values.

# ============================================================
# FORMAT RAW TABLES
# ============================================================
print("5/7  Corrupting raw fields and attaching enterprise metadata...")

def finalize_table(df, table_name, source, event_col, date_cols=None, id_cols=None, status_cols=None, nullable_cols=None, money_map=None, name_cols=None):
    with_meta, business_cols = add_metadata(df, source, event_col, table_name)
    return corrupt_business_columns(
        with_meta,
        business_cols,
        money_map=money_map,
        date_cols=set(date_cols or []),
        id_cols=set(id_cols or []),
        status_cols=set(status_cols or []),
        nullable_cols=set(nullable_cols or []),
        name_cols=set(name_cols or []),
    )

# Sales money needs currency from the same row.
df_sales_final = finalize_table(
    df_sales_raw_base,
    "raw_sales_orders",
    "SHOPIFY_OMS",
    "order_timestamp",
    date_cols=["order_timestamp", "customer_promised_delivery_date"],
    id_cols=["order_id", "sku_id", "warehouse_id"],
    status_cols=["status", "cancel_reason"],
    nullable_cols=["warehouse_id", "cancel_reason"],
    money_map={"unit_price_foreign": df_sales_raw_base["currency_code"].tolist(), "discount_amount_foreign": df_sales_raw_base["currency_code"].tolist()},
)

# Fulfillment uses event_timestamp.
df_fulfill_final = finalize_table(
    df_fulfill_truth,
    "raw_order_fulfillment_events",
    "SHOPIFY_OMS",
    "event_timestamp",
    date_cols=["event_timestamp"],
    id_cols=["order_id", "warehouse_id"],
    status_cols=["event_type"],
)

# Movement table uses event timestamp and IDs.
df_mov_final = finalize_table(
    df_mov_raw_base,
    "raw_inventory_movements",
    "BLUEYONDER_WMS",
    "movement_timestamp",
    date_cols=["movement_timestamp"],
    id_cols=["movement_id", "sku_id", "from_warehouse_id", "to_warehouse_id", "reference_id", "transfer_id"],
    status_cols=["movement_type"],
    nullable_cols=["from_warehouse_id", "to_warehouse_id"],
)

# Snapshots: dates are messy and the values are partly inconsistent by design.
df_snap_final = finalize_table(
    df_snap_truth,
    "raw_inventory_snapshots",
    "BLUEYONDER_WMS",
    "snapshot_date",
    date_cols=["snapshot_date", "source_timestamp"],
    id_cols=["warehouse_id", "sku_id"],
)

# Inject conflicting duplicate snapshots after final formatting.
if len(df_snap_final) > 50:
    dup_n = max(50, int(len(df_snap_final) * 0.003))
    picks = df_snap_final.sample(n=min(dup_n, len(df_snap_final)), random_state=SEED).copy()
    picks["on_hand_qty_raw"] = (pd.to_numeric(picks["on_hand_qty_raw"], errors="coerce") - np.random.randint(20, 70, size=len(picks))).fillna("N/A").astype(str)
    picks["record_updated_at"] = (pd.to_datetime(picks["record_updated_at"]) + pd.to_timedelta(30, unit="m")).dt.strftime("%Y-%m-%d %H:%M:%S")
    df_snap_final = pd.concat([df_snap_final, picks], ignore_index=True)

# PO uses currency + date logic.
df_po_final = finalize_table(
    df_po_truth,
    "raw_purchase_orders",
    "SAP_ARIBA",
    "po_date",
    date_cols=["po_date", "expected_delivery_date", "supplier_promised_ship_date"],
    id_cols=["po_id", "supplier_id", "sku_id", "warehouse_id"],
    status_cols=["status"],
    money_map={"unit_cost_foreign": df_po_truth["currency_code"].tolist()},
)

# Add deliberate duplicated PO lines with later updates.
if len(df_po_final) > 50:
    dup_n = max(10, int(len(df_po_final) * 0.005))
    picks = df_po_final.sample(n=min(dup_n, len(df_po_final)), random_state=SEED + 1).copy()
    picks["record_updated_at"] = (pd.to_datetime(picks["record_updated_at"]) + pd.to_timedelta(2, unit="h")).dt.strftime("%Y-%m-%d %H:%M:%S")
    df_po_final = pd.concat([df_po_final, picks], ignore_index=True)

# Shipments.
df_ship_final = finalize_table(
    df_ship_truth,
    "raw_inbound_shipments",
    "SAP_TM",
    "ship_date",
    date_cols=["supplier_handover_date", "ship_date", "expected_arrival_date"],
    id_cols=["shipment_id", "po_id", "tracking_id", "carrier_id", "destination_warehouse_id"],
)

# Carrier telemetry JSON: keep raw JSON as text, with epoch events inside.
df_telem_final = finalize_table(
    df_telemetry_truth,
    "raw_carrier_telemetry",
    "PROJECT44_API",
    "webhook_received_at" if "webhook_received_at" in df_telemetry_truth.columns else "tracking_id",
    date_cols=[],
    id_cols=["tracking_id", "shipment_id"],
)
# Add webhook_received_at_raw in a controlled way because metadata event time is not part of payload schema.
# The SQL side will rely on epochs inside carrier_payload_raw.

# Goods receipts.
df_receipt_final = finalize_table(
    df_receipt_raw_base,
    "raw_goods_receipts",
    "BLUEYONDER_WMS",
    "actual_receipt_date",
    date_cols=["actual_receipt_date", "putaway_date"],
    id_cols=["receipt_id", "po_id", "sku_id", "warehouse_id"],
)

# Masters.
df_product_final = finalize_table(
    df_product_raw_base,
    "raw_product_master_scd",
    "ERP_MDM",
    "effective_from",
    date_cols=["effective_from", "effective_to"],
    id_cols=["sku_id"],
    status_cols=["product_status"],
)

df_supplier_final = finalize_table(
    df_sup_truth,
    "raw_supplier_master",
    "ERP_MDM",
    "record_updated_at" if "record_updated_at" in df_sup_truth.columns else "supplier_id",
    date_cols=[],
    id_cols=["supplier_id"],
    name_cols=["supplier_name"],
)

df_warehouse_final = finalize_table(
    df_wh_truth,
    "raw_warehouse_master",
    "ERP_MDM",
    "warehouse_id",
    date_cols=[],
    id_cols=["warehouse_id"],
)

# Policy SCD finalization.
df_policy_final = finalize_table(
    df_policy_raw_base,
    "raw_sku_supplier_policy_scd",
    "ERP_MDM",
    "effective_from",
    date_cols=["effective_from", "effective_to"],
    id_cols=["supplier_id", "sku_id", "warehouse_id"],
)

# ============================================================
# MOCK FX API EXTRACT FOR LOCAL PIPELINE TESTING
# Replace this file with the real API-ingestion script later.
# ============================================================
print("6/7  Generating mock FX API extract for pipeline testing...")
fx_rows = []
for d in daterange(START_DATE.date(), END_DATE.date()):
    # Real API-style weekend gap.
    if d.weekday() >= 5:
        continue
    for curr in CURRENCIES:
        # A few weekday gaps.
        if random.random() < 0.015:
            continue
        fx_rows.append({
            "rate_date": datetime.combine(d, datetime.min.time()),
            "base_currency": curr,
            "target_currency": "INR",
            "exchange_rate": FX_TRUTH[(d, curr)],
        })

df_fx_truth = pd.DataFrame(fx_rows)
# Small amount of duplicate API observations.
if len(df_fx_truth) > 100:
    fx_dupes = df_fx_truth.sample(frac=0.01, random_state=SEED + 2).copy()
    fx_dupes["exchange_rate"] *= np.random.uniform(0.999, 1.001, size=len(fx_dupes))
    df_fx_truth = pd.concat([df_fx_truth, fx_dupes], ignore_index=True)

df_fx_final = finalize_table(
    df_fx_truth,
    "raw_fx_rates_api",
    "MOCK_FX_API",
    "rate_date",
    date_cols=["rate_date"],
    id_cols=["base_currency", "target_currency"],
    nullable_cols=["base_currency", "target_currency"],
)

# ============================================================
# EXPORT
# ============================================================
print("7/7  Exporting CSV files...")

exports = {
    "raw_sales_orders.csv": df_sales_final,
    "raw_order_fulfillment_events.csv": df_fulfill_final,
    "raw_inventory_movements.csv": df_mov_final,
    "raw_inventory_snapshots.csv": df_snap_final,
    "raw_purchase_orders.csv": df_po_final,
    "raw_inbound_shipments.csv": df_ship_final,
    "raw_carrier_telemetry.csv": df_telem_final,
    "raw_goods_receipts.csv": df_receipt_final,
    "raw_sku_supplier_policy_scd.csv": df_policy_final,
    "raw_product_master_scd.csv": df_product_final,
    "raw_supplier_master.csv": df_supplier_final,
    "raw_warehouse_master.csv": df_warehouse_final,
    "raw_fx_rates_api.csv": df_fx_final,
}

for filename, df in exports.items():
    path = os.path.join(OUTPUT_DIR, filename)
    df.to_csv(path, index=False)

print("\nNightmare Mode generation complete.")
print(f"Output folder: {os.path.abspath(OUTPUT_DIR)}")
print(f"Date range: {START_DATE.date()} to {END_DATE.date()}")
for filename, df in exports.items():
    print(f"  {filename:42s} {len(df):>8,} rows")

print("\nNext pipeline step:")
print("  1) Load these raw CSVs into BigQuery RAW tables.")
print("  2) Replace raw_fx_rates_api.csv with the real API ingestion when you build Script 2.")
print("  3) Build python_demand_forecast separately from cleaned BigQuery demand data.")
print("  4) Then start the SQL QUARANTINE -> STAGING -> RECONCILIATION -> MART layers.")
