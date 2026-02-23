# Compile Clean (No Artifact Drift)

Run compile + sync with strict artifact hygiene.

## Procedure
1. Run:
   - `./sync_and_compile.ps1 -MirrorSync`
2. Confirm compile success:
   - `0 errors`
3. Confirm temporary compile outputs are removed:
   - `compile_*.log`
   - `compile_*.txt`
   - `compile_logs.log`
4. Only keep artifacts when debugging explicitly requires:
   - `-KeepCompileArtifacts`

## Output contract
- compile result summary
- any remaining artifacts (should be none unless explicitly retained)
- next action if compilation failed
