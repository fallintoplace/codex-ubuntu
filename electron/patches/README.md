# patches

Ubuntu-specific desktop payload changes belong here.

Rules:

- keep patches narrow
- prefer one patch per concern
- separate launch-chain work from UI patching
- record which imported payload version a patch was validated against
- do not mix fallback-launcher fixes into the desktop payload patch layer

This directory is intentionally empty in the current intake phase.
The next step is to make the imported payload boundaries explicit before patching behavior.
