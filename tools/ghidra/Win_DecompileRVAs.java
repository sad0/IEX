// Decompile functions given by image-relative RVA (one hex RVA per line, optional "  label" after it).
// Usage (headless postScript args): <listFile> <outFile>
//   All results are concatenated into <outFile>, each preceded by "//==== <rva> <label>".
// @category IEX
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

import java.io.File;
import java.io.PrintWriter;
import java.nio.file.Files;

public class Win_DecompileRVAs extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            printerr("args: <listFile> <outFile>");
            return;
        }
        DecompInterface di = new DecompInterface();
        di.setOptions(new DecompileOptions());
        di.toggleCCode(true);
        di.openProgram(currentProgram);
        long base = currentProgram.getImageBase().getOffset();
        try (PrintWriter pw = new PrintWriter(args[1], "UTF-8")) {
            for (String raw : Files.readAllLines(new File(args[0]).toPath())) {
                String line = raw.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] p = line.split("\\s+", 2);
                long rva = Long.decode(p[0]);
                Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(base + rva);
                Function f = getFunctionAt(a);
                pw.println("//==== " + p[0] + " " + (p.length > 1 ? p[1] : ""));
                if (f == null) {
                    pw.println("// no function");
                    continue;
                }
                DecompileResults r = di.decompileFunction(f, 120, monitor);
                pw.println(r != null && r.decompileCompleted() ? r.getDecompiledFunction().getC()
                        : "// DECOMPILE FAILED");
            }
        }
    }
}
