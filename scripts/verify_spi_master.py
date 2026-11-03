"""Run the standalone SPI regression with the Vivado tools on PATH."""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "master/spi_sensor_master.sim/step4"
RTL = ROOT / "master/spi_sensor_master.srcs/sources_1/new/spi_master.v"
TB = ROOT / "master/spi_sensor_master.srcs/sim_1/new/tb_spi_master.v"


def run(tool, *args):
    executable = shutil.which(tool)
    if executable is None:
        raise RuntimeError(f"{tool} is missing from PATH; load the Vivado environment")
    print(f"Running {tool}...", flush=True)
    result = subprocess.run(
        [executable, *(arg.as_posix() if isinstance(arg, Path) else str(arg) for arg in args)],
        cwd=BUILD, capture_output=True,
        encoding="utf-8", errors="replace", timeout=180,
    )
    output = result.stdout + result.stderr
    (BUILD / f"{tool}-console.txt").write_text(output, encoding="utf-8")
    print(output, end="", flush=True)
    if result.returncode != 0 or re.search(r"^ERROR:", output, re.MULTILINE):
        raise RuntimeError(f"{tool} failed; see {BUILD}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--synth", action="store_true", help="run out-of-context synthesis instead of simulation")
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    if not args.synth:
        run("xvlog", RTL, TB)
        run("xelab", "work.tb_spi_master", "--debug", "typical", "--snapshot", "spi_master_test")
        sim_script = BUILD / "run.tcl"
        sim_script.write_text("log_wave -r /tb_spi_master/dut/*\nrun all\nquit\n", encoding="utf-8")
        output = run("xsim", "spi_master_test", "--tclbatch", sim_script, "--wdb", "spi_master.wdb")
        if "SPI_MASTER_TEST_PASS" not in output or re.search(r"^FAIL|SPI_MASTER_TEST_FAIL", output, re.MULTILINE):
            raise RuntimeError("self-checking simulation did not pass")
    if args.synth:
        synth_script = BUILD / "synth.tcl"
        synth_script.write_text(
            f"read_verilog {{{RTL.as_posix()}}}\n"
            "synth_design -top spi_master -part xc7a35tcpg236-1 -mode out_of_context\n"
            "create_clock -name sys_clk -period 10.0 [get_ports clk]\n"
            "report_utilization -file utilization.rpt\n"
            "report_timing_summary -file timing_synth.rpt\n"
            "set latches [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]\n"
            "if {[llength $latches] != 0} {error {Unexpected inferred latch}}\n"
            "set syncs [get_cells -hier -quiet -filter {ASYNC_REG == TRUE}]\n"
            "if {[llength $syncs] != 2} {error {MISO synchronizer attributes missing}}\n"
            "puts \"SPI_SYNTH_PASS latches=[llength $latches] async_regs=[llength $syncs]\"\n"
            "exit 0\n", encoding="utf-8",
        )
        output = run("vivado", "-mode", "batch", "-nojournal", "-source", synth_script)
        if "SPI_SYNTH_PASS" not in output:
            raise RuntimeError("synthesis checks did not finish")
    print(f"Verification complete. Generated logs, reports and waveform: {BUILD}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"Verification failed: {exc}", file=sys.stderr)
        sys.exit(1)
