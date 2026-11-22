# jaspr_anatomy example

A small server-rendered Jaspr site with deliberate reuse problems:

- a card and a button written by hand next to the components that render them (`lib/pages/home.dart`);
- three pricing tiers written inline (`lib/pages/pricing.dart`);
- two components that render the same structure, `InfoBox` and `Callout` (`lib/components/card.dart`).

It also has the shapes that are easy to get wrong: client components, an asynchronous component, raw HTML, a component that renders only text, and a table without `<tbody>`.

```sh
jaspr serve
```

Open <http://localhost:8080/?anatomy>, or press Alt+Shift+A on any page.

```sh
dart run jaspr_anatomy:inspect http://localhost:8080/ --crawl 5
dart run jaspr_anatomy:scan
```
