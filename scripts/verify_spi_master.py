"""Vivado CLI로 Master SPI와 센서 Transaction을 검증한다."""

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
READER = RTL.with_name("sensor_reader.v")
FND = RTL.with_name("fnd_controller.v")


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
    suite = parser.add_mutually_exclusive_group()
    suite.add_argument("--sensor", action="store_true", help="verify sensor_reader and its SPI connection")
    suite.add_argument("--fnd", action="store_true", help="verify FND formatting and SPI-to-display connection")
    args = parser.parse_args()
    global BUILD
    if args.sensor:
        BUILD = ROOT / "master/spi_sensor_master.sim/step5"
    elif args.fnd:
        BUILD = ROOT / "master/spi_sensor_master.sim/step6"
    BUILD.mkdir(parents=True, exist_ok=True)
    if not args.synth:
        if args.fnd:
            run("xvlog", RTL, READER, FND, TB.with_name("tb_fnd_controller.v"),
                TB.with_name("spi_sensor_peer.v"), TB.with_name("tb_sensor_display.v"))
            tests = [
                ("tb_fnd_controller", "FND_TEST_PASS"),
                ("tb_sensor_display", "SENSOR_DISPLAY_TEST_PASS"),
            ]
        elif args.sensor:
            run("xvlog", RTL, READER, TB.with_name("tb_sensor_reader.v"),
                TB.with_name("spi_sensor_peer.v"), TB.with_name("tb_sensor_transaction.v"))
            tests = [
                ("tb_sensor_reader", "SENSOR_READER_TEST_PASS"),
                ("tb_sensor_transaction", "SENSOR_TRANSACTION_TEST_PASS"),
            ]
        else:
            run("xvlog", RTL, TB)
            tests = [("tb_spi_master", "SPI_MASTER_TEST_PASS")]
        sim_script = BUILD / "run.tcl"
        for top, marker in tests:
            run("xelab", f"work.{top}", "--debug", "typical", "--snapshot", top)
            sim_script.write_text(f"log_wave -r /{top}/*\nrun all\nquit\n", encoding="utf-8")
            output = run("xsim", top, "--tclbatch", sim_script, "--wdb", f"{top}.wdb")
            (BUILD / f"{top}-console.txt").write_text(output, encoding="utf-8")
            if marker not in output or re.search(r"^FAIL|^\w+_TEST_FAIL", output, re.MULTILINE):
                raise RuntimeError(f"{top} self-checking simulation did not pass")
    if args.synth:
        rtl = FND if args.fnd else READER if args.sensor else RTL
        top = "fnd_controller" if args.fnd else "sensor_reader" if args.sensor else "spi_master"
        expected_syncs = 0 if args.sensor or args.fnd else 2
        marker = "FND_SYNTH_PASS" if args.fnd else "SENSOR_READER_SYNTH_PASS" if args.sensor else "SPI_SYNTH_PASS"
        synth_script = BUILD / "synth.tcl"
        synth_script.write_text(
            f"read_verilog {{{rtl.as_posix()}}}\n"
            f"synth_design -top {top} -part xc7a35tcpg236-1 -mode out_of_context\n"
            "create_clock -name sys_clk -period 10.0 [get_ports clk]\n"
            "report_utilization -file utilization.rpt\n"
            "report_timing_summary -file timing_synth.rpt\n"
            "set latches [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]\n"
            "if {[llength $latches] != 0} {error {Unexpected inferred latch}}\n"
            "set syncs [get_cells -hier -quiet -filter {ASYNC_REG == TRUE}]\n"
            f"if {{[llength $syncs] != {expected_syncs}}} {{error {{Unexpected synchronizer count}}}}\n"
            f"puts \"{marker} latches=[llength $latches] async_regs=[llength $syncs]\"\n"
            "exit 0\n", encoding="utf-8",
        )
        output = run("vivado", "-mode", "batch", "-nojournal", "-source", synth_script)
        if marker not in output:
            raise RuntimeError("synthesis checks did not finish")
    print(f"Verification complete. Generated logs, reports and waveform: {BUILD}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"Verification failed: {exc}", file=sys.stderr)
        sys.exit(1)
