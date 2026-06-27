# Rails 7 → 8 upgrade — reference checklist

Distilled from upgrading the Piazza app (Ruby 3.3 / Rails 7.2 → Ruby 3.4 / Rails
8.1). Ordered by how much time each item actually cost. Source:
`piazza-web/wip/analysis/01-upgrade-rails8-ruby34.md`.

## Strategy

- **Baseline first.** Get the app green on its *current* pinned versions before
  touching Rails. You want a working diff to bisect against.
- **Upgrade the framework gem, leave `config.load_defaults` where it is.**
  Bumping `rails` to `~> 8.1` while keeping `load_defaults 7.2` runs the new
  library code with old framework behavior — the low-risk path. Flip defaults to
  8.1 as a *separate* step via `config/initializers/new_framework_defaults_8_1.rb`
  (uncomment one line at a time, test between).
- Let `bundle update` resolve the graph; only hand-pin where a transitive
  conflict forces it, and document why.

## The expensive gotcha: flaky route-helper tests (LazyRouteSet)

If the test suite appends test-only routes via a helper that toggles
`Rails.application.routes.disable_clear_and_finalize`, Rails 8 will make it **flaky
under parallel test runs** — random `undefined method 'login_path'/'root_path'`
errors in unrelated controllers; serial runs stay green.

Two coupled causes:
1. **Stuck flag** — the helper sets `disable_clear_and_finalize = true` and never
   resets it, so a later `reload_routes!` stops clearing and app routes (named
   helpers) aren't restored for the rest of that parallel worker.
2. **LazyRouteSet materialization under the flag** — Rails 8 wraps app routes in a
   `LazyRouteSet`; `LazyRouteSet#draw` triggers materialization *itself*. If the
   helper set the flag *before* calling `draw`, the lazy reload of the app's own
   routes inherits the flag, redraws them **without finalizing**, and named helpers
   vanish inside the controller.

**Fix (what the linter checks / prints):**
1. Call `Rails.application.reload_routes_unless_loaded` **first**, flag still false,
   so app routes fully materialize + finalize.
2. Then set `disable_clear_and_finalize = true`, draw the test routes, and reset the
   flag to `false` in an `ensure` block.
3. `reload_routes!` should also force the flag false before reloading.
4. Every test that calls `draw_test_routes` needs a paired `teardown { reload_routes! }`.

> Dead end: adding `finalize!` to the `ensure` makes it *worse* — it re-evals
> appended blocks and marks the set finalized without rebuilding url helpers. The
> lever is **materialize-before-flag**, not finalize-after.

Corrected helper: `templates/routes_helper.rb.fixed`.

## Other items (cheaper)

- **pagy major.** pagy 6+ removed `pagy_link_proc` / `pagy_t`; pagy 9 splits
  frontend helpers and changes `Pagy.new`. If the app ships a custom pagy nav
  partial (e.g. a Bulma `_nav.html.erb`), bumping is a template+initializer port —
  pin `pagy ~> 5.x` and defer, or budget the rewrite. Don't let it block the Rails bump.
- **sidekiq 8 / redis 5 / kredis.** These coexist after `bundle update` (sidekiq 8
  uses redis-client; kredis is fine on redis-rb 5). No manual pinning needed in our case.
- **Ruby patch pin.** Bumping Ruby? Update the `ruby "x.y.z"` line in **both**
  `Gemfile` and the `RUBY VERSION` line in `Gemfile.lock`, or `bundle` refuses.
- **Deprecations.** Boot the app and run the suite with deprecations visible; flip
  `load_defaults` only after the gem bump is green.

## Verify

- Run the suite **multiple times** (≥6) — route/parallel flakes hide behind a
  single green run. A 35%-flake bug passes ~2 of 3 times.
- Boot the server, hit a public route (200) and a protected route (401/redirect).
