# Doczy: Markdown Documentation Browser

> Instantly view your Markdown docs in the browser!

Looking for a better way to browse your Markdown docs quickly and easily without jumping through the
hoops of setting up [mdBook](https://rust-lang.github.io/mdBook/),
[Sphinx](https://www.sphinx-doc.org/en/master/), or some other toolchain?

Use **Doczy!**

Navigate to the [test documentation index](docs/index.md) for an example.

Powered by Zig ![zig-zero](docs/imgs/zig-zero.png)

## Usage Example

```bash
zig build -Doptimize=ReleaseSmall
./zig-out/bin/doczy -f README.md
```
