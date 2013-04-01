Issues to resolve:

- Associated constants, types, etc
- Backtracking trait resolution
- "Eager" vtable resolution
  - hints for inference
  - only WriterUtil can ever have a method named `write_line` because
    method resolution doesn't consider trait bounds.  Should it do so
    eagerly?

## Proposed design

No 
