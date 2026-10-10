# Sample Schema — Sports Ticketing Database

A sample sports-ticketing database (MLB and NFL teams, players, stadiums,
seasons, tickets, and ticket transfer activity). It is handy for testing
migrations, generating realistic data volumes, and experimenting with queries.

The scripts were previously distributed as `db_scripts.zip`; they are now
unzipped under [`db_scripts/`](db_scripts/) so they can be browsed and diffed
directly on GitHub.

## Layout

```
db_scripts/
├── install-postgresql.sql     # top-level installer — run this
├── schema/
│   ├── create-table.sql       # table definitions
│   ├── create-index.sql       # indexes
│   ├── create-constraint.sql  # check/unique constraints
│   ├── foreign-keys.sql       # foreign keys (added after data load)
│   ├── create-view.sql        # views
│   └── functions/             # data-generation & loader functions
├── user/
│   └── create-user.sql        # creates the appuser role
└── data/
    └── csv/                   # seed data (teams, players, stadiums, names, ...)
```

## Installing

The installer uses `psql` meta-commands (`\i`, `\copy`), so run it from inside
the `db_scripts/` directory with `psql`:

```bash
cd db_scripts
createdb sampledb
psql -d sampledb -f install-postgresql.sql
```

`install-postgresql.sql` runs end to end:

1. Creates tables, indexes, and the `appuser` role (`search_path = appuser`).
2. Loads base CSV data (MLB/NFL data, names, stadiums, seat types, locations).
3. Generates teams, seats, players, and MLB/NFL seasons via SQL functions.
4. Generates sporting-event tickets and simulates ~5,000 purchases and
   ~100,000 transfer activities.
5. Backfills historical transaction timestamps, then adds foreign keys and
   views.

> Note: the loaders use `\copy` with relative paths (`./data/csv/...`), so the
> working directory must be `db_scripts/` when you run the installer.

## Source

This is the AWS Database Migration Service sample sports-ticketing database.
