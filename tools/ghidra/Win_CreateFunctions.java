// Create functions at a list of image-relative RVAs (hex, one per line) that analysis missed
// (e.g. leaf virtual functions only reachable through vtables when RTTI is off).
// Usage (headless postScript args): <listFile>
// @category IEX
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;

import java.io.File;
import java.nio.file.Files;

public class Win_CreateFunctions extends GhidraScript {
    @Override
    protected void run() throws Exception {
        long base = currentProgram.getImageBase().getOffset();
        int ok = 0, bad = 0;
        for (String raw : Files.readAllLines(new File(getScriptArgs()[0]).toPath())) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            Address a = toAddr(base + Long.decode(line));
            if (getFunctionContaining(a) != null) continue;
            if (getInstructionAt(a) == null) {
                new DisassembleCommand(a, null, true).applyTo(currentProgram, monitor);
            }
            if (createFunction(a, null) != null) ok++; else bad++;
        }
        println("created " + ok + " functions, failed " + bad);
    }
}
