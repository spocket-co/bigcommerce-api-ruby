# BigCommerce API Ruby — Spocket fork

Ruby client for the BigCommerce Stores API. Spocket uses it to push products into a dropshipper's
BigCommerce store, sync inventory and variants, and read and fulfil orders.

> ### This is a fork, and it has diverged in both directions
>
> Upstream is [`bigcommerce/bigcommerce-api-ruby`](https://github.com/bigcommerce/bigcommerce-api-ruby),
> and this repo is a real GitHub fork of it. Spocket branched from the `1.0.x` line and added the
> changes listed below. Upstream has since moved on to **2.0.0** — this fork is **41 commits
> behind** — so upstream's README, its Faraday 2 support and its current resource set do **not**
> describe this code.
>
> Everything below the *Spocket changes* section is upstream's own documentation, kept because it is
> still accurate for this fork. Where it is not, it has been corrected and the correction is
> flagged.
>
> **Do not `git pull` from upstream casually.** The two have incompatible dependency floors (see
> *Known gaps*).

## Spocket changes to upstream

| Change | What it does |
|---|---|
| **v2 → v3 by default** | `Config#api_url` now builds `.../stores/<hash>/v3/catalog` where upstream built `.../v2`. |
| **`api_version` config option** | Lets one process talk to **both** API versions — pass `api_version: 'v2'` for the endpoints BigCommerce never moved to v3. Blank or missing falls back to `v3/catalog`. |
| **`Bigcommerce::Variant`** | New resource on `variants/%d`, with a **`batch_update`** class method that `PUT`s an array of variants in one call. |
| **`Bigcommerce::ProductVariant`** | New subresource on `products/%d/variants/%d`. |
| **`PathBuilder`** | Added to `request.rb`; builds resource paths from a `%s`/`%d` template, chomping unused trailing segments. |
| URL path conversion fix | Corrects path building for the above. |
| JWT floor raised to `>= 2.10.3` | For **CVE-2026-45363**. **This is on `master` and is not what `rails-api` consumes** — see *Known gaps* item 1. |
| Version | `1.0.7` (upstream is `2.0.0`). |

Consumed by [`rails-api`](https://github.com/spocket-co/rails-api) only, across ~139 references.

## Tech stack

- **Ruby** — `>= 2.0.0` per this fork's gemspec (upstream now requires `>= 2.7.5`).
- **Faraday** and **faraday_middleware** — see *Known gaps* item 2; `master`'s gemspec and the
  commit `rails-api` actually uses disagree about the version.
- **Hashie 3.x** — every response is a `Hashie::Mash` subclass, so fields read as methods.
- **jwt** — used only by the Customer Login API token generation.
- **RSpec** — there is a real `spec/` suite here, unlike most gems in this family.

No CI: upstream's Travis and Gemnasium badges are long dead and have been removed from this README.
Nothing runs on a pull request in this fork.

## Local setup

The fork is private and is not on RubyGems, so `gem install bigcommerce` fetches **upstream's**
gem, not this one. It is consumed from git:

```ruby
# rails-api Gemfile
spocket_gem 'bigcommerce', '~> 1.0.7', repo: 'bigcommerce-api-ruby',
            ref: 'bc8ae6f0e9263608431c39b292c3fc0e996e26a4'
```

Note the **`ref:`** — unlike every other private gem in `rails-api`, this one is pinned to an exact
commit rather than tracked by branch. Read *Known gaps* item 1 before changing it.

To work on the gem itself:

```bash
git clone https://github.com/spocket-co/bigcommerce-api-ruby.git
cd bigcommerce-api-ruby
bundle install
bundle exec rspec
```

To test a change against `rails-api`, point the Gemfile at your working copy — the line is already
there, commented out, below the `spocket_gem` line.

## Environment variables

Eight, split into two groups. `.env.example` carries all of them, names only.

**Read by the library itself — one, optional:**

| Var | Required | What it is | Where to get it |
|---|---|---|---|
| `BC_API_ENDPOINT` | No | Overrides the API base URL in `Config#api_url`. Unset or empty falls back to `https://api.bigcommerce.com`. | Leave unset; set it only to point at a mock or proxy. `rails-api` does not set it. |

**Read by the scripts under `examples/` only** — not by `lib/`, and not by `rails-api`. They exist
so the example scripts can be run against a real store:

| Var | Used by | What it is |
|---|---|---|
| `BC_STORE_HASH` | every OAuth example | The store hash. |
| `BC_CLIENT_ID` | every OAuth example | App client id, from the Developer Portal's "My Apps". |
| `BC_ACCESS_TOKEN` | every OAuth example | Store access token from the OAuth token exchange. **Secret.** |
| `BC_CLIENT_SECRET` | `examples/customers/customer_login.rb` | App client secret, for Customer Login API tokens. **Secret.** |
| `BC_API_ENDPOINT_LEGACY` | `examples/configuration/legacy_auth.rb` | Legacy per-store API URL. |
| `BC_USERNAME` | `examples/configuration/legacy_auth.rb` | Legacy basic-auth username. |
| `BC_API_KEY` | `examples/configuration/legacy_auth.rb` | Legacy basic-auth API key. **Secret.** |

Inside the library, all of these are **config values** rather than environment reads — passed to
`Bigcommerce.configure` or `Config.new`: `store_hash`, `client_id`, `access_token`,
`client_secret`, `api_version`, and for legacy auth `auth`, `url`, `username`, `api_key`.

> **`rails-api` does not use any of the `BC_*` names.** It supplies the credentials from
> **`BIGCOMMERCE_CLIENT_ID`** and **`BIGCOMMERCE_CLIENT_SECRET`**, with the store hash and access
> token coming from the `IntegratedStore` record rather than from the environment. So if you are
> tracing a production credential, `BC_CLIENT_ID` is the wrong thing to grep for — it only ever
> applies to the example scripts.

## Architecture and key concepts

**Two API versions, one process.** This is the Spocket-specific part and the thing most likely to
confuse. `Config#api_url` returns `<base>/stores/<store_hash>/<api_version>`, defaulting
`api_version` to `v3/catalog`. BigCommerce never migrated some endpoints to v3, so `rails-api`
keeps **a connection per version**, memoized by version:

```ruby
# rails-api, app/models/integrated_store.rb
def on_bigcommerce(api_version: nil)
  @connections ||= {}
  @connections[api_version] ||= Bigcommerce::Connection.build(
    Bigcommerce::Config.new(
      store_hash: uid,
      client_id: ENV['BIGCOMMERCE_CLIENT_ID'],
      access_token: credential.token,
      api_version: api_version
    )
  )
end
```

`on_bigcommerce` (no argument) gives you **v3 catalog**; `on_bigcommerce(api_version: 'v2')` gives
you v2. Orders, shipments, webhooks and store info all go through v2 in `rails-api`; products,
categories and variants through v3. **Getting this wrong produces a 404 from BigCommerce, not a
local error.**

**Resource methods are generated, not written.** `ResourceActions.new(uri: ...)` and
`SubresourceActions.new(uri: ...)` are `Module` subclasses; including one defines `all`, `find`,
`create`, `update`, `destroy` and `destroy_all` (the subresource variants taking a leading
`parent_id`). So grepping a resource file for `def find` finds nothing — only overrides such as
`Variant.batch_update` are written by hand. `PathBuilder` fills the `%s`/`%d` slots and chomps
trailing ones when fewer ids are supplied, which is how one template serves both `all` and `find`.

**A connection is per store**, since `store_hash` and the access token are baked into it — hence the
memoization above, and hence `configure` being unsuitable for a multi-tenant app (see *Thread
Safety*).

**Errors.** `Middleware::HttpException` maps HTTP statuses onto `Bigcommerce::HttpError` subclasses.
`rails-api` rescues `HttpError` and `InternalServerError` in its BigCommerce handlers.

There are **45 resource classes** under `lib/bigcommerce/resources/`, grouped by domain
(`products/`, `orders/`, `customers/`, `shipping/`, `store/`, `system/`, `tax/`, `webhooks/`,
`payments/`).

---

The remainder of this section is **upstream's documentation**, corrected where this fork differs.

## Authentication

Two schemes, depending on the use case.

### OAuth

OAuth apps can be submitted to the [BigCommerce App Store](https://www.bigcommerce.com/apps),
allowing merchants to install them in their stores. This is what Spocket uses.
[More information](https://developer.bigcommerce.com/api/using-oauth-intro).

The resources you can reach depend on the **scopes the merchant granted** your app — see
[OAuth Scopes](https://developer.bigcommerce.com/api/scopes).

### Basic Authentication (Legacy)

For a custom integration against a single store.
[More information](https://developer.bigcommerce.com/api/legacy/basic-auth). Spocket does not use
this path; it is still present in the code.

## Configuration

### OAuth app

- `client_id` — from the [Developer Portal's](http://developer.bigcommerce.com) "My Apps" section.
- `access_token` — obtained after the token exchange in the auth callback.
- `store_hash` — also obtained after the token exchange.

```rb
Bigcommerce.configure do |config|
  config.store_hash   = '<store-hash>'
  config.client_id    = '<client-id>'
  config.access_token = '<access-token>'
  config.api_version  = 'v2'    # Spocket addition; omit for v3/catalog
end
```

### Customer Login API

To generate storefront login tokens you also need the app's client secret:

```rb
Bigcommerce.configure do |config|
  config.store_hash    = '<store-hash>'
  config.client_id     = '<client-id>'
  config.client_secret = '<client-secret>'
end
```

## Usage

See the [examples folder](examples) and BigCommerce's
[developer documentation](https://developer.bigcommerce.com/api). Those scripts read their
credentials from the `BC_*` environment variables listed above.

```rb
Bigcommerce.configure do |config|
  config.store_hash   = '<store-hash>'
  config.client_id    = '<client-id>'
  config.access_token = '<access-token>'
end

Bigcommerce::System.time
# => #<Bigcommerce::System time=1466801314>
```

The Spocket-added batch update:

```rb
Bigcommerce::Variant.batch_update(
  [{ id: 1, price: 10.0 }, { id: 2, price: 12.0 }],
  connection: connection
)
```

### Thread safety

**`Bigcommerce.configure` is NOT thread-safe.** It is designed for single-tenant applications and
CLIs. For a multi-tenant or threaded app — which is what `rails-api` is — build a connection per
store and pass it explicitly:

```rb
connection = Bigcommerce::Connection.build(
  Bigcommerce::Config.new(
    store_hash:   '<store-hash>',
    client_id:    '<client-id>',
    access_token: '<access-token>'
  )
)

Bigcommerce::System.time(connection: connection)
Bigcommerce::System.raw_request(:get, 'time', connection: connection)
```

Legacy auth, for completeness:

```rb
connection_legacy = Bigcommerce::Connection.build(
  Bigcommerce::Config.new(
    auth:     'legacy',
    url:      '<legacy-api-endpoint>',
    username: '<username>',
    api_key:  '<api-key>'
  )
)
```

The connection is a plain `Faraday::Connection`, so you can build your own or swap adapters.

## Testing

Unlike most private gems in this family, **this one has a real RSpec suite** — inherited from
upstream, under `spec/bigcommerce/unit/`, with a spec per resource.

```bash
bundle exec rspec
```

The suite is offline; it does not call BigCommerce.

**But it has drifted from upstream.** Diffing against upstream `master` shows this fork is missing
`spec/simplecov_helper.rb`, `spec/support/helpers.rb` and `spec/bigcommerce/unit/subresource_actions_spec.rb`,
with `spec/spec_helper.rb` also reduced. Coverage reporting is gone and the subresource-action
generator — which every subresource depends on — is now untested here. Note also that neither of the
two Spocket-added resources (`Variant`, `ProductVariant`) has a spec, and `Variant.batch_update` is
hand-written code with no test at all.

There is no CI, so nobody finds out when the suite breaks.

## Deploy and release

Nothing deploys from this repo. It is a library, consumed from git by `rails-api`.

There is no CI, no publish workflow, and this fork is never pushed to RubyGems (upstream owns the
`bigcommerce` gem name there).

To ship a change:

1. Open a PR against `master` (**the default branch is `master`, not `main`**).
2. After merge, bump `Bigcommerce::VERSION` in `lib/bigcommerce/version.rb` and add a `CHANGELOG.md`
   entry — this repo does keep a changelog, so keep it up.
3. Tag with a **`v` prefix** — the 14 existing tags are `v1.0.1` … `v1.0.7`. That is the opposite
   convention from the other private Spocket gems, which use bare versions. Match what is here.
4. **Update the `ref:` in `rails-api`'s Gemfile to the new commit SHA** and run
   `bundle update bigcommerce`. Because of the exact-commit pin, a merge to `master` alone ships
   nothing — this step is what deploys it. See *Known gaps* item 1.
5. Ship `rails-api` as normal.

## Troubleshooting and gotchas

| Symptom | Cause |
|---|---|
| A request 404s against a resource you know exists | Wrong API version. Orders, shipments, webhooks and store info are **v2**; products, categories and variants are **v3**. Pass `api_version: 'v2'` where needed. |
| Requests go to `v3/catalog` unexpectedly | `api_version` was blank, nil or whitespace — all fall back to `v3/catalog`. |
| A change merged to `master` has no effect in `rails-api` | `rails-api` pins an exact `ref:`. Merging is not shipping; the Gemfile SHA must be updated too. |
| `bundle update bigcommerce` fails on a Faraday conflict | `master` and the pinned commit declare **different Faraday floors**. See *Known gaps* item 2. |
| `gem install bigcommerce` gives you different code | That is upstream's gem on RubyGems, currently `2.0.0`. This fork is `1.0.7` and diverged. |
| Something works in upstream's README and not here | Upstream is 41 commits and one major version ahead. Its README does not describe this code. |
| A resource file has no `find`/`create` method | They are generated by `ResourceActions` / `SubresourceActions` at include time. |
| A connection appears to talk to the wrong store | `store_hash` and the token are baked into the connection. Build one per store; do not reuse. |
| `Bigcommerce.configure` behaves oddly under concurrency | It is explicitly not thread-safe. Pass `connection:` instead. |
| Grepping for `BC_CLIENT_ID` finds nothing | Those names are upstream's examples. `rails-api` uses `BIGCOMMERCE_CLIENT_ID` / `_SECRET`. |

## Known gaps

Code and configuration issues found while writing this. Listed here rather than fixed, because this
is a documentation change.

1. **`rails-api` is pinned to a commit that is not on `master`, and `master`'s security fix is
   therefore not deployed.** The Gemfile pins
   `ref: 'bc8ae6f0e9263608431c39b292c3fc0e996e26a4'`, which lives **only** on the unmerged branch
   `origin/matt/faraday-version-bump` — `git merge-base --is-ancestor` confirms it is not an
   ancestor of `master`. So the three most recent commits on `master`, including
   `fix/jwt-security-cve-2026-45363` (which raises the `jwt` floor to `>= 2.10.3`) and the
   blank-`api_version` handling plus its new specs, are **not in the deployed gem**.

   To be accurate about the impact: `rails-api`'s `Gemfile.lock` currently resolves `jwt (2.10.3)`
   anyway, so it is **not vulnerable today**. The problem is that nothing *enforces* that floor
   from this gem — the pinned commit asks only for `jwt (>= 2.1.0)` — and that a merged security fix
   is sitting undeployed while the deployed code lives on a branch nobody is likely to look at.
   Someone should reconcile `master` and that branch and move the pin.

2. **`master` and the pinned commit declare incompatible Faraday floors.** `master`'s gemspec says
   `faraday '~> 0.11'` / `faraday_middleware '~> 0.11'`, which excludes Faraday 1.x. The pinned
   commit says `'~> 1.0'` for both, and `rails-api` resolves `faraday (1.10.6)`. So simply moving
   the pin to `master` would fail to resolve — which may well be why the branch exists. Upstream,
   meanwhile, is on `faraday >= 2.14` with `faraday-gzip`. Any real fix here is a three-way Faraday
   decision, not a one-line pin change.

3. **This fork is 41 commits behind upstream `master`** and a major version behind (`1.0.7` vs
   `2.0.0`). It is missing upstream's Faraday 2 support, `frozen_string_literal` pragmas, the
   `>= 2.7.5` Ruby floor and `rubygems_mfa_required`. Whether to rebase the Spocket changes onto
   upstream 2.0.0 or to keep diverging is a decision worth making deliberately rather than by
   drift.

4. **The two Spocket-added resource files carry copy-pasted comments describing something else.**
   `product_variant.rb` is headed "Product Image / Images associated with a product" and
   `variant.rb` is headed "SKU / Stock Keeping Unit identifiers associated with products". Both also
   link to **v2** documentation URLs while the fork defaults to v3. This is the ticket's
   "stale/misleading comments" item.

5. **Spec coverage was lost in the fork.** `spec/simplecov_helper.rb`, `spec/support/helpers.rb` and
   `spec/bigcommerce/unit/subresource_actions_spec.rb` are all present upstream and absent here, and
   `spec_helper.rb` is reduced. The subresource generator is untested, and neither Spocket-added
   resource — including the hand-written `Variant.batch_update` — has a spec.

6. **No CI.** There is a real test suite and nothing runs it on a pull request. Of everything in
   this list, this is the cheapest to fix.

7. **Dead badges.** Upstream's Travis and Gemnasium badges were in this README; both services are
   long gone. Removed here.

8. **The gemspec still identifies upstream** — `authors: ['BigCommerce Engineering']` and a
   `homepage` pointing at upstream. The MIT licence and copyright are genuinely theirs and should
   stay; the contact fields are misleading for a fork Spocket maintains.

9. **`CONTRIBUTING.md`, `RELEASING.md` and `DEPENDENCIES.md` are upstream's** and describe
   upstream's process (RubyGems releases, upstream's review). They do not apply to this fork. Left
   in place rather than deleted, but they need either updating or a note.

No committed credentials, no non-English log strings, and no leftover task markers.

## Ownership

Spocket engineering. Questions in **#engineering**.

Consumed exclusively by `rails-api`; changes here affect the BigCommerce product push, inventory and
variant sync, and order fulfilment. Owner to confirm the specific team and support channel, and to
resolve *Known gaps* items 1 and 2 — the pin and the Faraday floors — which together determine what
is actually running in production.

## Licence

MIT, upstream's. See [LICENSE.md](LICENSE.md).
