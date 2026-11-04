// In-memory repair of bogus "no return" flags left by auto-analysis (it marks some ordinary
// functions, e.g. CAIObjectType::CAIObjectType, as non-returning, which truncates every caller).
// For each function flagged noreturn whose name is not a genuine noreturn routine, clear the flag,
// disassemble the fall-through after each call site and fix the caller's body.
// Run it as the first -postScript; with -readOnly nothing is saved to the project.
// Optional arg: <reportFile> listing what was changed.
// @category IEX
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.FlowOverride;
import ghidra.program.model.symbol.Reference;

import java.io.File;
import java.io.PrintWriter;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.regex.Pattern;

public class FixNoReturn extends GhidraScript {
    private static final Pattern GENUINE = Pattern.compile(
        "(?i).*(abort|exit|terminate|__cxa_throw|__cxa_rethrow|__cxa_bad|__throw|__stack_chk_fail|"
        + "longjmp|unwind_resume|_Unwind_Resume|assert_fail|panic|fatal|__cxa_pure_virtual|"
        + "__cxa_call_unexpected|SDL_TriggerBreakpoint|raise).*");

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        PrintWriter pw = args.length > 0 ? new PrintWriter(new File(args[0]), "UTF-8") : null;
        Set<Function> fixed = new LinkedHashSet<>();
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            if (!f.hasNoReturn()) continue;
            String n = f.getName(true);
            if (GENUINE.matcher(n).matches()) continue;
            f.setNoReturn(false);
            fixed.add(f);
        }
        Set<Function> callers = new LinkedHashSet<>();
        int removed = 0;
        Set<Address> sites = new LinkedHashSet<>();
        for (Function f : fixed) {
            for (Reference r : getReferencesTo(f.getEntryPoint())) {
                if (!r.getReferenceType().isCall()) continue;
                Instruction ins = getInstructionAt(r.getFromAddress());
                if (ins == null) continue;
                if (ins.getFlowOverride() == FlowOverride.CALL_RETURN) ins.setFlowOverride(FlowOverride.NONE);
                Address ft = ins.getMaxAddress().next();
                ins.setFallThrough(ft);
                if (getInstructionAt(ft) == null) disassemble(ft);
                // analysis may have started a bogus FUN_xxx at the fall-through: drop it so the
                // caller's body can grow back over it
                Function bogus = getFunctionAt(ft);
                if (bogus != null && bogus.getName().startsWith("FUN_")) {
                    removeFunction(bogus);
                    removed++;
                }
                sites.add(r.getFromAddress());
            }
        }
        // resolve callers only after all removals (a caller may itself have been a bogus FUN_)
        for (Address site : sites) {
            Function c = getFunctionContaining(site);
            if (c == null) c = getFunctionBefore(site);
            if (c != null) callers.add(c);
        }
        for (Function c : callers) {
            try {
                CreateFunctionCmd.fixupFunctionBody(currentProgram, c, monitor);
            } catch (Exception e) {
                printerr("fixup failed for " + c.getName(true) + ": " + e.getMessage());
            }
        }
        if (pw != null) {
            for (Function f : fixed) pw.println("cleared noreturn: " + f.getName(true) + " @ " + f.getEntryPoint());
            pw.println("callers fixed: " + callers.size() + ", bogus FUN_ removed: " + removed);
            pw.close();
        }
        println("FixNoReturn: cleared " + fixed.size() + " functions, fixed " + callers.size() + " callers, removed " + removed + " bogus FUN_");
    }
}
