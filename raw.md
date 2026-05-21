---
title: Streaming Markdown fixtures
tags:
  - parser
  - renderer
draft: false
---

# Front matter

Front matter is rendered as a metadata block when it appears at the top of the
document.

---

Thematic breaks render as horizontal dividers.

***

Underscore breaks are supported too.

---

# Heading level 1

## Heading level 2

### Heading level 3

#### Heading level 4

##### Heading level 5

###### Heading level 6

Setext heading level 1
======================

Setext heading level 2
----------------------

Paragraph text keeps normal Markdown prose readable while streaming. A newline
inside the same paragraph remains part of the rendered text.

---

# Inline formatting

This paragraph includes **bold**, __bold with underscores__, *italic*,
_italic with underscores_, ***bold italic***, ___bold italic underscores___,
~~strikethrough~~, and `inline code`.

Nested emphasis also works: **bold text with _italic inside_ and `code`**.

Unclosed delimiters can render during streaming: **bold while the chunk is still
arriving.

---

# Links and references

Inline links render as tappable spans: [OpenAI](https://openai.com).

Autolinks render from angle brackets: <https://github.com>.

Full reference links work with definitions: [Flutter docs][flutter].

Collapsed references use the label as the key: [Dart][].

Shortcut references work too: [pub.dev].

[flutter]: https://docs.flutter.dev
[dart]: https://dart.dev
[pub.dev]: https://pub.dev

---

# Images

![Remote demo image](https://picsum.photos/seed/streaming-markdown/960/360)

Inline images inside a paragraph are represented inline:
before ![small marker](https://picsum.photos/seed/marker/120/120) after.

---

# Lists and tasks

- Unordered item
- Item with **inline formatting**
  - Nested unordered item
  - Another nested item
    - Third level item

1. Ordered item
2. Ordered item starting from the source number
   1. Nested ordered item
   2. Another nested ordered item

- [x] Completed task
- [ ] Open task
- [X] Uppercase completed task

---

# Block quotes and callouts

> A normal block quote keeps quoted prose visually separate.
> It can span more than one line.

> [!NOTE] Note
> Notes render with an info treatment.

> [!TIP] Tip
> Tips render with a success treatment.

> [!IMPORTANT] Important
> Important callouts have their own accent.

> [!WARNING] Warning
> Warnings render with a warning accent.

> [!CAUTION] Caution
> Caution callouts render with an error accent.

---

# Code blocks

```dart
class Greeter {
  const Greeter(this.name);

  final String name;

  String call() => 'Hello, $name';
}
```

~~~json
{
  "streaming": true,
  "blocks": ["paragraph", "code", "table"]
}
~~~

    final value = 'Indented code block';
    print(value);

---

# Tables

| Case | Markdown | Rendered behavior |
| :--- | :------: | ---------------: |
| Inline code | `a | b` | Keeps pipe inside code |
| Escaped pipe | `a \| b` | Keeps escaped separator |
| Link | [docs](https://docs.flutter.dev) | Tappable cell content |

| Name | Status | Notes |
| --- | --- | --- |
| Alpha | Ready | Basic cells |
| Beta | Streaming | **Formatted** cell |

---

# Footnotes

Streaming render can show footnote references inline.[^parser]

Multiple references can point at separate definitions.[^renderer]

[^parser]: The parser emits footnote definition nodes.
[^renderer]: The renderer displays definitions as compact rows.

---

<section>
  <h2>HTML block</h2>
  <p>HTML blocks render with Flutter widgets, including <strong>strong</strong>,
  <em>emphasis</em>, <code>inline code</code>, and
  <a href="https://dart.dev">links</a>.</p>
  <blockquote>Nested HTML block quotes are supported.</blockquote>
  <ul>
    <li>HTML unordered item</li>
    <li>Second unordered item</li>
  </ul>
  <ol>
    <li>HTML ordered item</li>
    <li>Second ordered item</li>
  </ol>
  <table>
    <thead>
      <tr><th>Column</th><th>Value</th></tr>
    </thead>
    <tbody>
      <tr><td>HTML table</td><td>Rendered</td></tr>
    </tbody>
  </table>
  <p>Line break<br>inside a paragraph.</p>
  <img src="https://picsum.photos/seed/html-block/700/240" alt="HTML image">
  <hr>
</section>
