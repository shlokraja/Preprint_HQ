-- TODO: Move this to a Dockerfile later

-- To setup the db with this file
-- docker pull postgres:9.3
-- docker run --name <container_name> -e POSTGRES_PASSWORD=<passwd> -p 5432:5432 -d postgres:9.3
-- psql -h localhost -U postgres
-- postgres=# create user agniva with password 'passwd';
-- postgres=# create database foodbox with owner agniva;
-- psql -h localhost -U postgres -d foodbox -c 'CREATE EXTENSION pgcrypto;'
-- psql -h localhost -U agniva -d foodbox -f schema.sql
--

START TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- Setting the timezone to a local one
ALTER DATABASE foodbox SET timezone to 'Asia/Kolkata';

-- Setting datestyle to dd/mm/yyyy
SET datestyle to 'iso, dmy';

-- Creating the types
CREATE TYPE payment_method AS ENUM ('cash', 'card');
CREATE TYPE food_item_location AS ENUM ('dispenser', 'outside', 'supplies');
CREATE TYPE food_item_category AS ENUM('staple', 'fast moving', 'slow moving');
CREATE TYPE purchase_order_status AS ENUM ('packing', 'in transit', 'in outlet');
CREATE TYPE po_final_status AS ENUM ('sold', 'expired', 'spoiled', 'unable to scan (Rest. fault)', 'scanner fault (Foodbox fault)', 'damaged in transit', 'damaged while dispensing', 'improperly sealed', 'undelivered', 'not dispatched', 'quantity', 'quality', 'packing', 'other');
CREATE TYPE sales_issue AS ENUM ('sold', 'refund', 'replaced');
CREATE TYPE sales_status AS ENUM ('original', 'modified');
CREATE TYPE user_group_name AS ENUM ('hq', 'outlet', 'restaurant');
CREATE TYPE user_role AS ENUM ('generic', 'hq_executive', 'hq_sales', 'hq_operations', 'hq_accounting', 'hq_customer_management', 'restaurant_staff', 'restaurant_owner', 'outlet_staff');
CREATE TYPE user_permission AS ENUM ('admin', 'normal');
CREATE TYPE supplies_phase AS ENUM ('start_of_day', 'end_of_day');
CREATE TYPE dispense_status AS ENUM ('pending', 'dispensing', 'delivered', 'timeout');
CREATE TYPE non_food_issue_types AS ENUM ('Transportation:Other',
'Operations:Supplies not available',
'Operations:Employee absent',
'Operations:Pest problem',
'Operations:Menu Image problem',
'Operations:Other',
'Facilities:Electrical Fault',
'Facilities:Power cut',
'Facilities:A/C fault',
'Facilities:Plumbing & Drainage',
'Facilities:Appliance not working',
'Facilities:Signage Problem',
'Facilities:Other',
'Dispenser:Compressor fault',
'Dispenser:Control Power-On fault',
'Dispenser:Air On Fault',
'Dispenser:Dispenser gripper fault',
'Dispenser:Dispenser door fault',
'Dispenser:Mic door fault',
'Dispenser:Piercing cyl raise fault',
'Dispenser:Mic gripper fault',
'Dispenser:Lane servo fault',
'Dispenser:Food crash',
'Dispenser:X/Y axis fault',
'Dispenser:Door limit fault',
'Dispenser:Scanner problem',
'Dispenser:Other',
'IT:Menu Display issue',
'IT:Order tablet problem',
'IT:Card payment problem',
'IT:Internet problem',
'IT:Intranet connectivity issue',
'IT:Application problem',
'IT:Other',
'Restaurant:Heat Sealer problem',
'Restaurant:Arduino problem',
'Restaurant:Facilities issue',
'Restaurant:Application problem',
'Restaurant:Printer problem',
'Restaurant:Bluetooth problem',
'Restaurant:Internet problem',
'Restaurant:Intranet connectivity issue',
'Restaurant:Other',
'Uncategorized:Uncategorized issue',
'Snacks and Beverages:Quality',
'Snacks and Beverages:Quantity',
'Snacks and Beverages:Other'
);
CREATE TYPE shift_phase AS ENUM ('shift_start', 'shift_end');
CREATE TYPE city_enum AS ENUM ('CH', 'BN');
CREATE TYPE report_user_type AS ENUM('FV', 'HQ');

-- Creating the tables
CREATE TABLE IF NOT EXISTS restaurant (
  id serial PRIMARY KEY,
  name varchar(50) NOT NULL,
  short_name text,
  address text,
  contact_name varchar(50),
  phone_no  bigint NOT NULL,
  st_no varchar(20),
  tin_no  bigint,
  account_no  bigint,
  beneficiary_name varchar(50),
  neft_code varchar(50),
  bank_name varchar(50),
  branch_name varchar(50),
  active boolean,
  start_of_day time,
  pan_no varchar(20),
  location varchar(80),
  entity varchar(50)
);

CREATE TABLE IF NOT EXISTS outlet (
  id serial PRIMARY KEY,
  name varchar(50) NOT NULL,
  short_name text,
  address text,
  start_of_day  time NOT NULL,
  end_of_day  time NOT NULL,
  num_ordering_screens  integer NOT NULL,
  num_live_ordering_screens  integer NOT NULL,
  cash_at_start integer,
  active boolean,
  force_print_bill boolean,
  is24hr boolean,
  abatement_percent real,
  payment_methods  payment_method[] NOT NULL,
  city city_enum,
  phone_no  varchar(15)
  CONSTRAINT num_screen_constraint CHECK(num_live_ordering_screens <= num_ordering_screens)
);

CREATE TABLE IF NOT EXISTS food_item_master (
  id serial PRIMARY KEY,
  name varchar(80) NOT NULL,
  ingredients1a varchar(40),
  ingredients1b varchar(40),
  ingredients2 varchar(40),
  ingredients3 varchar(40),
  restaurant_id integer REFERENCES restaurant(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS food_item (
  id serial PRIMARY KEY,
  name varchar(80) NOT NULL,
  item_tag varchar(50) NOT NULL,
  restaurant_id integer REFERENCES restaurant(id) ON DELETE CASCADE ON UPDATE CASCADE,
  outlet_id integer REFERENCES outlet(id) ON DELETE CASCADE ON UPDATE CASCADE,
  expiry_time text NOT NULL,
  side_order text,
  ingredients1a varchar(40),
  ingredients1b varchar(40),
  ingredients2 varchar(40),
  ingredients3 varchar(40),
  veg boolean NOT NULL,
  heating_required boolean,
  location  food_item_location NOT NULL,
  cuisine TEXT,
  category  food_item_category,
  packaging_cost  real,
  production_cost real,
  purchase_price  real,
  selling_price  real,
  mrp real,
  service_tax_percent real,
  vat_percent real,
  foodbox_fee real,
  restaurant_fee real,
  master_id integer DEFAULT 0,
  gf_id integer
);

-- This function checks and assigns master_id for every new food_item inserted into table.
CREATE OR REPLACE FUNCTION assign_master_id() RETURNS TRIGGER AS $food_item_pre_insert_trigger$
DECLARE master_id integer;
  BEGIN
    SELECT fim.id INTO master_id
      FROM food_item_master fim
      WHERE LOWER(fim.name) = LOWER(NEW.name)
      AND LOWER(fim.ingredients1a) = LOWER(NEW.ingredients1a)
      AND LOWER(fim.ingredients1b) = LOWER(NEW.ingredients1b)
      AND LOWER(fim.ingredients2) = LOWER(NEW.ingredients2)
      AND LOWER(fim.ingredients3) = LOWER(NEW.ingredients3)
      AND fim.restaurant_id = NEW.restaurant_id
      LIMIT 1;

    IF (master_id > 0) THEN
      NEW.master_id := master_id;
      RETURN NEW;
    ELSE
      -- Insert new row into food_item_master
      INSERT INTO food_item_master (name, ingredients1a, ingredients1b, ingredients2, ingredients3, restaurant_id)
        VALUES (NEW.name, NEW.ingredients1a, NEW.ingredients1b, NEW.ingredients2, NEW.ingredients3, NEW.restaurant_id);
      NEW.master_id = (SELECT currval(pg_get_serial_sequence('food_item_master', 'id')));
      RETURN NEW;
    END IF;
  END;
$food_item_pre_insert_trigger$ LANGUAGE plpgsql;

CREATE TRIGGER food_item_pre_insert_trigger
BEFORE INSERT ON food_item
  FOR EACH ROW EXECUTE PROCEDURE assign_master_id();

-- This function updates item_tag for food_item
CREATE OR REPLACE FUNCTION update_food_item_tag() RETURNS TRIGGER AS $food_item_post_insert_trigger$
  DECLARE
    fv_fi_index integer;
    fv_short_name varchar;
  BEGIN
    IF (NEW.item_tag != '') THEN
        RETURN NULL;
    END IF;

    SELECT count(*) into fv_fi_index
      FROM food_item_master
      WHERE restaurant_id = NEW.restaurant_id;

    SELECT short_name into fv_short_name
      FROM restaurant
      WHERE restaurant.id = NEW.restaurant_id
      LIMIT 1;

    UPDATE food_item
      SET item_tag = (fv_short_name || '-' || fv_fi_index)
      WHERE id = NEW.id;
    RETURN NULL;
  END;
$food_item_post_insert_trigger$ LANGUAGE plpgsql;

CREATE TRIGGER food_item_post_insert_trigger
AFTER INSERT ON food_item
  FOR EACH ROW EXECUTE PROCEDURE update_food_item_tag();


CREATE TABLE IF NOT EXISTS special_timings (
  start_time time NOT NULL,
  end_time time NOT NULL,
  outlet_id integer REFERENCES outlet(id) ON DELETE CASCADE ON UPDATE CASCADE,
  slot_name varchar(50),
  CONSTRAINT special_timings_constraint UNIQUE(start_time, end_time, outlet_id)
);

CREATE TABLE IF NOT EXISTS bundles (
  food_item_id integer REFERENCES food_item(id) ON DELETE CASCADE ON UPDATE CASCADE,
  bundle_item_id integer REFERENCES food_item(id) ON DELETE CASCADE ON UPDATE CASCADE,
  discount_percent real,
  CONSTRAINT bundles_constraint UNIQUE(food_item_id, bundle_item_id)
);

CREATE TABLE IF NOT EXISTS user_group (
  id serial PRIMARY KEY,
  name user_group_name,
  -- target_id will be either rest_id, outlet_id or -1(hq).
  target_id integer
);

CREATE TABLE IF NOT EXISTS atp_user (
  id serial PRIMARY KEY,
  full_name text NOT NULL,
  username varchar(50) NOT NULL,
  salt text,
  password_hash text,
  email varchar(50),
  -- from group_id we can infer if the user is part of hq/outlet/fv.
  -- and also which outlet/fv does he/she belong to.
  group_id integer REFERENCES user_group(id) ON UPDATE CASCADE,
  -- there will be specific set of roles that a user can belong to depending
  -- on the user_group he/she is in.
  roles user_role[],
  permission user_permission
);

CREATE TABLE IF NOT EXISTS atp_user_shifts (
  user_id integer REFERENCES atp_user(id) ON UPDATE CASCADE,
  shift shift_phase,
  time timestamp with time zone
);
CREATE INDEX on atp_user_shifts(time);

CREATE TABLE IF NOT EXISTS session (
  name varchar(50) NOT NULL,
  start_time  time NOT NULL,
  end_time  time NOT NULL,
  outlet_id integer REFERENCES outlet(id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT session_constraint UNIQUE(name, outlet_id)
);

CREATE TABLE IF NOT EXISTS purchase_order (
  id serial PRIMARY KEY,
  outlet_id integer REFERENCES outlet(id) ON DELETE SET NULL ON UPDATE CASCADE,
  restaurant_id integer REFERENCES restaurant(id) ON DELETE SET NULL ON UPDATE CASCADE,
  restaurant_staff_id integer REFERENCES atp_user(id) ON DELETE SET NULL ON UPDATE CASCADE,
  volume_forecast_id integer,
  green_signal_time timestamp with time zone,
  scheduled_delivery_time timestamp with time zone
);
CREATE INDEX on purchase_order(green_signal_time);
CREATE INDEX on purchase_order(scheduled_delivery_time);

CREATE TABLE IF NOT EXISTS purchase_order_master_list (
  purchase_order_id integer REFERENCES purchase_order(id) ON DELETE CASCADE ON UPDATE CASCADE,
  food_item_id integer REFERENCES food_item(id) ON DELETE SET NULL ON UPDATE CASCADE,
  quantity integer NOT NULL,
  CONSTRAINT purchase_order_constraint UNIQUE(purchase_order_id, food_item_id)
);

CREATE TABLE IF NOT EXISTS purchase_order_batch (
  id integer,
  purchase_order_id integer REFERENCES purchase_order(id) ON DELETE CASCADE ON UPDATE CASCADE,
  barcode varchar(24) NOT NULL,
  quantity integer NOT NULL,
  delivery_time timestamp with time zone,
  received_time timestamp with time zone,
  CONSTRAINT delivery_batch_constraint UNIQUE(id, purchase_order_id, barcode)
);
CREATE INDEX on purchase_order_batch(id);
CREATE INDEX on purchase_order_batch(purchase_order_id);

CREATE TABLE IF NOT EXISTS purchase_order_final_status (
  id serial PRIMARY KEY,
  batch_id integer,
  purchase_order_id integer REFERENCES purchase_order(id) ON DELETE CASCADE ON UPDATE CASCADE,
  barcode varchar(24) NOT NULL,
  food_item_id integer REFERENCES food_item(id),
  quantity integer NOT NULL,
  status po_final_status,
  problem TEXT,
  note TEXT,
  resolution_status TEXT DEFAULT 'in progress'
);

CREATE TABLE IF NOT EXISTS supplies (
  food_item_id integer REFERENCES food_item(id) ON DELETE SET NULL ON UPDATE CASCADE,
  quantity real,
  time timestamp with time zone,
  phase supplies_phase NOT NULL
);

CREATE TABLE IF NOT EXISTS supplies_master_list (
  food_item_id integer REFERENCES food_item(id) ON DELETE CASCADE ON UPDATE CASCADE,
  restaurant_id integer REFERENCES restaurant(id) ON DELETE CASCADE ON UPDATE CASCADE,
  outlet_id integer REFERENCES outlet(id) ON DELETE CASCADE ON UPDATE CASCADE,
  image_url TEXT
);

CREATE TABLE IF NOT EXISTS non_food_issue (
  id serial PRIMARY KEY,
  outlet_id integer REFERENCES outlet(id) ON DELETE CASCADE ON UPDATE CASCADE,
  type non_food_issue_types,
  note TEXT,
  reporter TEXT,
  time timestamp with time zone,
  resolution_status TEXT DEFAULT 'pending'
);
CREATE INDEX on non_food_issue(time);

CREATE TABLE IF NOT EXISTS test_mode_issue (
  outlet_id integer REFERENCES outlet(id) ON DELETE CASCADE ON UPDATE CASCADE,
  issue TEXT,
  start_time timestamp with time zone,
  end_time timestamp with time zone,
  issue_time timestamp with time zone
);

CREATE TABLE IF NOT EXISTS sales_order (
  id serial PRIMARY KEY,
  outlet_id integer REFERENCES outlet(id) ON DELETE SET NULL ON UPDATE CASCADE,
  time timestamp with time zone NOT NULL,
  counter_code integer,
  method payment_method,
  mobile_num text,
  cardholder_name text,
  card_no text
);
CREATE INDEX on sales_order(time);

CREATE TABLE IF NOT EXISTS sales_order_items (
  sales_order_id integer REFERENCES sales_order(id) ON DELETE CASCADE ON UPDATE CASCADE,
  food_item_id integer REFERENCES food_item(id) ON DELETE SET NULL ON UPDATE CASCADE,
  quantity integer NOT NULL,
  barcode varchar(24) NOT NULL
);

CREATE TABLE IF NOT EXISTS live_stock (
  id serial PRIMARY KEY,
  outlet_id integer REFERENCES outlet(id) ON DELETE SET NULL ON UPDATE CASCADE,
  time timestamp with time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS live_stock_items (
  live_stock_id integer REFERENCES live_stock(id) ON DELETE CASCADE ON UPDATE CASCADE,
  food_item_id integer REFERENCES food_item(id) ON DELETE SET NULL ON UPDATE CASCADE,
  quantity integer NOT NULL
);

CREATE TABLE IF NOT EXISTS sales_order_payments (
  sales_order_id integer REFERENCES sales_order(id) ON DELETE CASCADE ON UPDATE CASCADE,
  amount_due real,
  amount_collected real,
  issue sales_issue,
  status sales_status
);

CREATE TABLE IF NOT EXISTS petty_cash (
  amount integer,
  note text,
  outlet_id integer REFERENCES outlet(id) ON DELETE SET NULL ON UPDATE CASCADE,
  time timestamp with time zone NOT NULL
);
CREATE INDEX on petty_cash(time);

CREATE TABLE IF NOT EXISTS bill_items (
  sales_order_id integer REFERENCES sales_order(id) ON DELETE CASCADE ON UPDATE CASCADE,
  bill_no integer NOT NULL,
  food_item_id integer REFERENCES food_item(id) ON DELETE SET NULL ON UPDATE CASCADE,
  quantity integer NOT NULL,
  dispense_status dispense_status
);
CREATE INDEX on bill_items(bill_no);

CREATE TABLE IF NOT EXISTS transporter_log (
  purchase_order_id integer REFERENCES purchase_order(id) ON DELETE CASCADE ON UPDATE CASCADE,
  batch_id integer,
  signature text
);

CREATE TABLE IF NOT EXISTS outlet_plc_config (
  lane_count integer,
  async_scan boolean,
  dispenser_slot_count integer,
  plc_type integer DEFAULT 0,
  plc_ip inet,
  plc_port integer,
  item_dispense_timeout_secs integer,
  outlet_id integer REFERENCES outlet(id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT plc_config_constraint UNIQUE(outlet_id),
  CONSTRAINT lane_count_constraint CHECK(lane_count > 0)
);

CREATE TABLE IF NOT EXISTS outlet_crash_recovery (
  bill_no integer,
  dispense_id bigint,
  outlet_id integer REFERENCES outlet(id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT outlet_id_constraint UNIQUE(outlet_id)
);

CREATE TABLE IF NOT EXISTS restaurant_config (
  restaurant_id integer REFERENCES restaurant(id) ON DELETE CASCADE ON UPDATE CASCADE,
  firebase_url text,
  printer_ip text,
  sender_email text,
  max_print_count integer,
  test_template text
);

-- This table stores the mobile no. of the customer along with the no. of transactions that he/she has done.
CREATE TABLE IF NOT EXISTS customer_details (
  mobile_no text,
  num_transactions integer,
  total_expenditure integer,
  total_savings integer,
  CONSTRAINT mobile_no_constraint UNIQUE(mobile_no)
);

CREATE TABLE IF NOT EXISTS tag_master_list (
  tag TEXT,
  CONSTRAINT tag_constraint UNIQUE(tag)
);

-- This table stores the tags for an issue
CREATE TABLE IF NOT EXISTS issue_tags (
  id serial PRIMARY KEY,
  referer_id integer,
  issue_type TEXT,
  tag TEXT
);

-- This table stores the status updates done on an issue
CREATE TABLE IF NOT EXISTS status_log (
  referer_id integer,
  issue_type text,
  status_text text,
  time timestamp with time zone
);

CREATE TABLE IF NOT EXISTS menu_bands (
  id serial PRIMARY KEY,
  start_time time NOT NULL,
  end_time time NOT NULL,
  name TEXT,
  outlet_id integer REFERENCES outlet(id)
);

CREATE TABLE IF NOT EXISTS po_timings (
  id serial PRIMARY KEY,
  outlet_id integer REFERENCES outlet(id),
  fv_id integer REFERENCES restaurant(id),
  po_time time
);

CREATE TABLE IF NOT EXISTS menu_plans (
  menu_band_id integer REFERENCES menu_bands(id),
  food_item_id integer REFERENCES food_item(id),
  quantity integer,
  sent boolean,
  generated_ts timestamp with time zone,
  target_ts timestamp with time zone
);

CREATE TABLE IF NOT EXISTS vf_intervals (
  outlet_id integer REFERENCES outlet(id),
  time_gap interval,
  last_run_date date
);

-- This table stores the amount of discount applicable to the no. of transactions done by the customer
CREATE TABLE IF NOT EXISTS discount_details(
  num_transactions integer,
  discount_percent real
);

-- This table stores daily consolidated cash settlement for an outlet as a json object.
CREATE TABLE IF NOT EXISTS daily_cash_settlements(
  outlet_id integer REFERENCES outlet(id),
  creation_time timestamp with time zone,
  consolidated_data json,
  last_updated timestamp with time zone
);

-- This table stores consolidated bill bundle
CREATE TABLE IF NOT EXISTS daily_bills(
  outlet_id integer REFERENCES outlet(id),
  bill_date Date,
  consolidated_data json,
  CONSTRAINT daily_bills_constraint UNIQUE(outlet_id, bill_date)
);

-- This table stores escrow accounts per city.
CREATE TABLE IF NOT EXISTS escrow_accounts(
  city city_enum,
  account_name VARCHAR(50),
  bank_name VARCHAR(50),
  bank_address TEXT,
  bank_branch VARCHAR(50),
  account_no VARCHAR(50),
  corp_name VARCHAR(100),
  agreement_date DATE,
  correspondent_email VARCHAR(50),
  CONSTRAINT escrow_accounts_constraint UNIQUE(city)
);

CREATE TABLE IF NOT EXISTS util (
 key TEXT,
 value json,
 CONSTRAINT key_constraint UNIQUE(key)
);

-- This table is for storing service tax and VAT per city per fv.
CREATE TABLE IF NOT EXISTS taxes(
  city city_enum,
  restaurant_id integer REFERENCES restaurant(id) ON DELETE CASCADE ON UPDATE CASCADE,
  service_tax_percent real DEFAULT 0,
  vat_percent real DEFAULT 0,
  CONSTRAINT taxes_constraint UNIQUE(city, restaurant_id)
);

-- This table is for storing city based abatement taxes.
CREATE TABLE IF NOT EXISTS abatements(
  city city_enum,
  abatement_percent real DEFAULT 0,
  tds_percent real DEFAULT 0,
  foodbox_service_tax_percent real DEFAULT 0,
  CONSTRAINT abatement_constraint UNIQUE(city)
);

-- This function updates food_item table every time taxes table is modified.
CREATE OR REPLACE FUNCTION update_taxes() RETURNS TRIGGER AS $food_item_taxes$
  DECLARE
    abt_perc real;
    old_st real;
    new_st real;
    old_vat real;
    new_vat real;
    eff_st_old real;
    eff_st_new real;
    diff_factor real;

  BEGIN
    IF (TG_OP = 'INSERT') THEN
      old_vat := 0;
      new_vat := NEW.vat_percent;
      old_st := 0;
      new_st := NEW.service_tax_percent;
    END IF;

    IF (TG_OP = 'UPDATE') THEN
      -- forbid updates that changes restaurant_id or city --
      IF (OLD.restaurant_id != NEW.restaurant_id) THEN
        RAISE EXCEPTION 'Update of restuarant id not allowed.';
      END IF;

      IF (OLD.city != NEW.city) THEN
        RAISE EXCEPTION 'Update of city not allowed.';
      END IF;
      old_vat := OLD.vat_percent;
      new_vat := NEW.vat_percent;
      old_st := OLD.service_tax_percent;
      new_st := NEW.service_tax_percent;
    END IF;

    SELECT abatement_percent into abt_perc
      FROM outlet
      WHERE outlet.city = NEW.city;

    eff_st_old := old_st*abt_perc/100;
    eff_st_new := new_st*abt_perc/100;
    diff_factor := (1.0/(100 + eff_st_new + new_vat) - 1.0/(100 + eff_st_old + old_vat));

    UPDATE food_item
      SET
        restaurant_fee = restaurant_fee*(1 + mrp*100*diff_factor/selling_price),
        foodbox_fee = foodbox_fee*(1 + mrp*100*diff_factor/selling_price),
        selling_price = mrp*100/(100 + eff_st_new + new_vat),
        vat_percent = new_vat,
        service_tax_percent = new_st
      WHERE
        restaurant_id = NEW.restaurant_id
        AND
        outlet_id in (SELECT id FROM outlet WHERE outlet.city = NEW.city)
        AND
        location = 'dispenser';
    RETURN NULL;
  END;
$food_item_taxes$ LANGUAGE plpgsql;

CREATE TRIGGER food_item_taxes
AFTER INSERT OR UPDATE ON taxes
  FOR EACH ROW EXECUTE PROCEDURE update_taxes();

-- This function updates outlet table every time city based abatements are modified.
CREATE OR REPLACE FUNCTION update_abatements() RETURNS TRIGGER AS $outlet_abatements$
  DECLARE
    old_abatement real;
    new_abatement real;

  BEGIN
    IF(TG_OP = 'INSERT') THEN
      old_abatement := 100;
      new_abatement := NEW.abatement_percent;
    END IF;

    IF (TG_OP = 'UPDATE') THEN
      IF (OLD.city != NEW.city) THEN
        RAISE EXCEPTION 'Update of city not allowed.';
      END IF;
      old_abatement := OLD.abatement_percent;
      new_abatement := NEW.abatement_percent;
    END IF;

    UPDATE outlet
      SET abatement_percent = NEW.abatement_percent
      WHERE
        city = NEW.city;

    UPDATE food_item
      SET
        restaurant_fee = restaurant_fee*(1 + mrp*100*(1.0/(100 + service_tax_percent*new_abatement/100 + vat_percent) - 1.0/(100 + service_tax_percent*old_abatement/100 + vat_percent))/selling_price),
        foodbox_fee = foodbox_fee*(1 + mrp*100*(1.0/(100 + service_tax_percent*new_abatement/100 + vat_percent) - 1.0/(100 + service_tax_percent*old_abatement/100 + vat_percent))/selling_price),
        selling_price = mrp*100/(100 + service_tax_percent*new_abatement/100 + vat_percent)
      WHERE
        outlet_id in (SELECT id FROM outlet WHERE outlet.city = NEW.city)
        AND
        location = 'dispenser';

    RETURN NULL;
  END;
$outlet_abatements$ LANGUAGE plpgsql;

CREATE TRIGGER outlet_abatements
AFTER INSERT OR UPDATE ON abatements
  FOR EACH ROW EXECUTE PROCEDURE update_abatements();

-- This table stores auth details for an entity
CREATE TABLE IF NOT EXISTS account_reports_user(
  entity VARCHAR(50) PRIMARY KEY,
  username VARCHAR(50) NOT NULL,
  password_hash VARCHAR(100) NOT NULL,
  usertype report_user_type,
  CONSTRAINT account_reports_user_constraint UNIQUE(username)
);

-- This function does md5 hashing of account reports user password.
CREATE OR REPLACE FUNCTION encrypt_account_reports_password() RETURNS TRIGGER AS $account_reports_user_pre_insert_trigger$
  BEGIN
    NEW.password_hash = crypt(NEW.password_hash, gen_salt('md5'));
    RETURN NEW;
  END;
$account_reports_user_pre_insert_trigger$ LANGUAGE plpgsql;

CREATE TRIGGER account_reports_user_pre_insert_trigger
BEFORE INSERT ON account_reports_user
  FOR EACH ROW EXECUTE PROCEDURE encrypt_account_reports_password();


-- This table keeps track of FTR carry forward
CREATE TABLE IF NOT EXISTS ftr_carry_forward(
  entity VARCHAR(50) NOT NULL,
  carry_forward real NOT NULL DEFAULT 0,
  city city_enum,
  ftr_date Date,
  CONSTRAINT ftr_carry_over_constraint UNIQUE(entity, city, ftr_date)
);

-- This stores old PO/sales data from gofrugal database.
CREATE TABLE IF NOT EXISTS gofrugal_po_sales(
  sales_date Date NOT NULL,
  mr_code VARCHAR(50) NOT NULL,
  status po_final_status,
  item_id integer,
  item_name VARCHAR(50),
  outlet_id integer NOT NULL DEFAULT -1,
  restaurant_id integer NOT NULL DEFAULT -1,
  selling_price real,
  mrp real,
  vat_percent real,
  service_tax_percent real,
  tds_percent real,
  foodbox_fee real,
  restaurant_fee real,
  session VARCHAR(20),
  ispo boolean,  
);

-- This function wipes the bill if there was a dispensing problem
CREATE OR REPLACE FUNCTION wipe_bill(bill_no_p integer, food_item_id_p integer) RETURNS integer AS
$$
DECLARE
rows_affected integer := 0;
food_price real := 0;
BEGIN
select sum(quantity) into rows_affected from bill_items where bill_no=$1 and food_item_id=$2;
-- If only 1 row in the bill, then delete everything
IF rows_affected > 1 THEN
  -- decrementing the bill_item by 1
  update bill_items set quantity=quantity-1 where bill_no=$1 and food_item_id=$2;

  -- decrement sales_order_item by 1
  update sales_order_items set quantity=quantity-1 where sales_order_id=(select sales_order_id from bill_items where bill_no=$1 and food_item_id=$2 limit 1) and food_item_id=$2;

  -- decrement sales_order_payments by that price
  select mrp into food_price from food_item where id=$2;
  update sales_order_payments set amount_collected=amount_collected-food_price, amount_due=amount_due-food_price where sales_order_id=(select sales_order_id from bill_items where bill_no=$1 and food_item_id=$2 limit 1);
ELSE
  DELETE from sales_order WHERE id=(select sales_order_id from bill_items where bill_no=$1  and food_item_id=$2 limit 1);
END IF;

GET DIAGNOSTICS rows_affected = ROW_COUNT;
RETURN rows_affected;
END
$$
LANGUAGE plpgsql;

-- This function decodes a base36 string to base 10 integer
CREATE OR REPLACE FUNCTION base36_decode(IN base36 varchar)
  RETURNS bigint AS $$
        DECLARE
      a char[];
      ret bigint;
      i int;
      val int;
      chars varchar;
    BEGIN
    chars := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

    FOR i IN REVERSE char_length(base36)..1 LOOP
      a := a || substring(upper(base36) FROM i FOR 1)::char;
    END LOOP;
    i := 0;
    ret := 0;
    WHILE i < (array_length(a,1)) LOOP
      val := position(a[i+1] IN chars)-1;
      ret := ret + (val * (36 ^ i));
      i := i + 1;
    END LOOP;

    RETURN ret;

END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- This function decides what the dispense_status should be depending on
-- the item id whether it is in dispenser or outside
CREATE OR REPLACE FUNCTION get_dispense_status(food_item_id integer)
RETURNS TEXT AS $$
      DECLARE
      row record;
BEGIN
  select location into row from food_item where id=food_item_id;
  IF row.location = 'dispenser' THEN
   return 'pending';
  ELSE
   return 'delivered';
  END IF;
END;
$$ LANGUAGE plpgsql;

-- This function computes the tasks needed at end of day
CREATE OR REPLACE FUNCTION eod_calculation(outlet_id_p integer) RETURNS integer AS
$$
DECLARE
rows_affected integer := 0;
row record;
start_time supplies.time%TYPE;
BEGIN
CREATE TEMPORARY TABLE temp_table
(
  count integer,
  barcode VARCHAR(24)
)
ON COMMIT DROP;

select start_of_day, end_of_day into row from outlet where id=$1;
IF row.end_of_day > row.start_of_day THEN
  insert into temp_table select sum(quantity) count, barcode from sales_order_items si, sales_order s where si.sales_order_id=s.id and s.outlet_id=$1 and s.time::date = current_date group by barcode;

  -- Updating the status of the properly sold items
  with batch_details as (select id, purchase_order_id, count, pb.barcode from purchase_order_batch pb, temp_table t where pb.barcode=t.barcode and count > 0) insert into purchase_order_final_status (batch_id, purchase_order_id, barcode, food_item_id, quantity, status, problem, note) select batch_details.id, batch_details.purchase_order_id, batch_details.barcode, base36_decode(substring(batch_details.barcode from 9 for 4))::integer, batch_details.count, 'sold', '', '' from batch_details;

  -- Updating the status for undelivered items by calculating the delta
  with batch_details as (
   select pb.id as batch_id, pb.purchase_order_id, pb.barcode, sum(pb.quantity) as count from purchase_order_batch pb, purchase_order p where pb.purchase_order_id=p.id and p.scheduled_delivery_time::date = current_date and p.outlet_id=$1 group by pb.barcode, pb.id, pb.purchase_order_id ),
  final_status_details as (
  select pf.batch_id, pf.purchase_order_id, pf.barcode, sum(pf.quantity) as count from purchase_order_final_status pf, purchase_order p where pf.purchase_order_id=p.id and p.scheduled_delivery_time::date = current_date and p.outlet_id=$1 group by pf.barcode, pf.batch_id, pf.purchase_order_id)
  insert into purchase_order_final_status (batch_id, purchase_order_id, barcode, food_item_id, quantity, status, problem, note) select batch_details.batch_id, batch_details.purchase_order_id, batch_details.barcode, base36_decode(substring(batch_details.barcode from 9 for 4))::integer, batch_details.count - final_status_details.count, 'undelivered','','' from batch_details, final_status_details where batch_details.batch_id=final_status_details.batch_id and batch_details.purchase_order_id=final_status_details.purchase_order_id and batch_details.barcode=final_status_details.barcode and (batch_details.count - final_status_details.count) > 0;

  -- Now setting those items which do not have a barcode in the final status table at all, setting them to undelivered too.
  with batch_details as (
   select pb.id as batch_id, pb.purchase_order_id, pb.barcode, sum(pb.quantity) as count from purchase_order_batch pb, purchase_order p where pb.purchase_order_id=p.id and p.scheduled_delivery_time::date = current_date and p.outlet_id=$1 group by pb.barcode, pb.id, pb.purchase_order_id )
  insert into purchase_order_final_status (batch_id, purchase_order_id, barcode, food_item_id, quantity, status, problem, note) select batch_details.batch_id, batch_details.purchase_order_id, batch_details.barcode, base36_decode(substring(batch_details.barcode from 9 for 4))::integer, batch_details.count, 'undelivered','','' from batch_details where batch_details.barcode not in (
  select pf.barcode from purchase_order_final_status pf, purchase_order p where pf.purchase_order_id=p.id and p.scheduled_delivery_time::date = current_date and p.outlet_id=$1 group by pf.barcode, pf.batch_id, pf.purchase_order_id);

  -- Now need to set the status for any items which were not picked up at all, but
  -- were in the po_master_list, means they were packed
  with batch_details as (
   select  pb.purchase_order_id, base36_decode(substring(barcode from 9 for 4))::integer as food_item_id, sum(pb.quantity) as count from purchase_order_batch pb, purchase_order p where pb.purchase_order_id=p.id and p.scheduled_delivery_time::date=current_date and p.outlet_id=$1 group by pb.barcode, pb.purchase_order_id),
  master_list_details as (
  select p.id as purchase_order_id,pm.food_item_id,quantity from purchase_order p, purchase_order_master_list pm where p.id=pm.purchase_order_id and p.scheduled_delivery_time::date=current_date and p.outlet_id=$1)
  insert into purchase_order_final_status (batch_id, purchase_order_id, barcode, food_item_id, quantity, status, problem, note)
  select -1,  m.purchase_order_id, '', m.food_item_id, sum(m.quantity)-sum(coalesce(b.count,0)), 'not dispatched', '','' from master_list_details m left join batch_details b on m.purchase_order_id=b.purchase_order_id and m.food_item_id=b.food_item_id group by m.purchase_order_id, m.food_item_id having  sum(m.quantity)-sum(coalesce(b.count,0)) > 0;

  RETURN 1;
ELSE
  select time from supplies s, food_item f into start_time where s.food_item_id=f.id and f.outlet_id=$1 and phase='start_of_day' order by time desc limit 1;

  IF start_time IS NULL THEN
    start_time := '01/01/2015'::timestamp;
  END IF;

  insert into temp_table select sum(quantity) count, barcode from sales_order_items si, sales_order s where si.sales_order_id=s.id and s.outlet_id=$1 and s.time > start_time group by barcode;

  -- Updating the status of the properly sold items
  with batch_details as (select id, purchase_order_id, count, pb.barcode from purchase_order_batch pb, temp_table t where pb.barcode=t.barcode and count > 0) insert into purchase_order_final_status (batch_id, purchase_order_id, barcode, food_item_id, quantity, status, problem, note) select batch_details.id, batch_details.purchase_order_id, batch_details.barcode, base36_decode(substring(batch_details.barcode from 9 for 4))::integer, batch_details.count, 'sold', '', '' from batch_details;

  -- Updating the status for undelivered items by calculating the delta
  with batch_details as (
   select pb.id as batch_id, pb.purchase_order_id, pb.barcode, sum(pb.quantity) as count from purchase_order_batch pb, purchase_order p where pb.purchase_order_id=p.id and p.scheduled_delivery_time > start_time and p.outlet_id=$1 group by pb.barcode, pb.id, pb.purchase_order_id ),
  final_status_details as (
  select pf.batch_id, pf.purchase_order_id, pf.barcode, sum(pf.quantity) as count from purchase_order_final_status pf, purchase_order p where pf.purchase_order_id=p.id and p.scheduled_delivery_time > start_time and p.outlet_id=$1 group by pf.barcode, pf.batch_id, pf.purchase_order_id)
  insert into purchase_order_final_status (batch_id, purchase_order_id, barcode, food_item_id, quantity, status, problem, note) select batch_details.batch_id, batch_details.purchase_order_id, batch_details.barcode, base36_decode(substring(batch_details.barcode from 9 for 4))::integer, batch_details.count - final_status_details.count, 'undelivered','','' from batch_details, final_status_details where batch_details.batch_id=final_status_details.batch_id and batch_details.purchase_order_id=final_status_details.purchase_order_id and batch_details.barcode=final_status_details.barcode and (batch_details.count - final_status_details.count) > 0;

  -- Now setting those items which do not have a barcode in the final status table at all, setting them to undelivered too.
  with batch_details as (
   select pb.id as batch_id, pb.purchase_order_id, pb.barcode, sum(pb.quantity) as count from purchase_order_batch pb, purchase_order p where pb.purchase_order_id=p.id and p.scheduled_delivery_time > start_time and p.outlet_id=$1 group by pb.barcode, pb.id, pb.purchase_order_id )
  insert into purchase_order_final_status (batch_id, purchase_order_id, barcode, food_item_id, quantity, status, problem, note) select batch_details.batch_id, batch_details.purchase_order_id, batch_details.barcode, base36_decode(substring(batch_details.barcode from 9 for 4))::integer, batch_details.count, 'undelivered','','' from batch_details where batch_details.barcode not in (
  select pf.barcode from purchase_order_final_status pf, purchase_order p where pf.purchase_order_id=p.id and p.scheduled_delivery_time > start_time and p.outlet_id=$1 group by pf.barcode, pf.batch_id, pf.purchase_order_id);

  -- Now need to set the status for any items which were not picked up at all, but
  -- were in the po_master_list, means they were packed
  with batch_details as (
   select  pb.purchase_order_id, base36_decode(substring(barcode from 9 for 4))::integer as food_item_id, sum(pb.quantity) as count from purchase_order_batch pb, purchase_order p where pb.purchase_order_id=p.id and p.scheduled_delivery_time > start_time and p.outlet_id=$1 group by pb.barcode, pb.purchase_order_id),
  master_list_details as (
  select p.id as purchase_order_id,pm.food_item_id,quantity from purchase_order p, purchase_order_master_list pm where p.id=pm.purchase_order_id and p.scheduled_delivery_time::date > start_time and p.outlet_id=$1)
  insert into purchase_order_final_status (batch_id, purchase_order_id, barcode, food_item_id, quantity, status, problem, note)
  select -1,  m.purchase_order_id, '', m.food_item_id, sum(m.quantity)-sum(coalesce(b.count,0)), 'not dispatched', '','' from master_list_details m left join batch_details b on m.purchase_order_id=b.purchase_order_id and m.food_item_id=b.food_item_id group by m.purchase_order_id, m.food_item_id having  sum(m.quantity)-sum(coalesce(b.count,0)) > 0;

  RETURN -1;
END IF;

END
$$
LANGUAGE plpgsql;

COMMIT;
