-- One Postgres instance, one schema per service. Keeps the "database per service"
-- boundary honest without running four containers on a laptop.
CREATE SCHEMA IF NOT EXISTS orders;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS payments;
CREATE SCHEMA IF NOT EXISTS notifications;
