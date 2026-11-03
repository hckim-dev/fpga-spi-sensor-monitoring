"""Vivado CLI로 Master SPI·센서·출력을 검증한다."""

import argparse
import hashlib
import json
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
UART = RTL.with_name("uart_reporter.v")
UART_TX = RTL.with_name("uart_tx.v")
RESET = RTL.with_name("reset_sync.v")
TOP = RTL.with_name("spi_sensor_master_top.v")
I2C = RTL.with_name("i2c_master.v")
XDC = ROOT / "master/spi_sensor_master.srcs/constrs_1/imports/digilent-xdc-master/Basys-3-Master.xdc"


def run(tool, *args, timeout=180):
    executable = shutil.which(tool)
    if executable is None:
        raise RuntimeError(f"{tool} is missing from PATH; load the Vivado environment")
    print(f"Running {tool}...", flush=True)
    result = subprocess.run(
        [executable, *(arg.as_posix() if isinstance(arg, Path) else str(arg) for arg in args)],
        cwd=BUILD, capture_output=True,
        encoding="utf-8", errors="replace", timeout=timeout,
    )
    output = result.stdout + result.stderr
    (BUILD / f"{tool}-console.txt").write_text(output, encoding="utf-8")
    print(output, end="", flush=True)
    if result.returncode != 0 or re.search(r"^(?:ERROR:|CRITICAL WARNING:)", output, re.MULTILINE):
        raise RuntimeError(f"{tool} failed; see {BUILD}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--synth", action="store_true", help="run synthesis instead of simulation")
    mode.add_argument("--impl", action="store_true", help="place, route and generate bitstream; requires --top")
    suite = parser.add_mutually_exclusive_group()
    suite.add_argument("--sensor", action="store_true", help="verify sensor_reader and its SPI connection")
    suite.add_argument("--fnd", action="store_true", help="verify FND formatting and SPI-to-display connection")
    suite.add_argument("--uart", action="store_true", help="verify UART bytes, reports and SPI connection")
    suite.add_argument("--top", action="store_true", help="verify board top, reset, selection and LEDs")
    suite.add_argument("--i2c", action="store_true", help="verify OLED I2C write transport")
    args = parser.parse_args()
    if args.impl and not args.top:
        parser.error("--impl requires --top")
    global BUILD
    if args.sensor:
        BUILD = ROOT / "master/spi_sensor_master.sim/step5"
    elif args.fnd:
        BUILD = ROOT / "master/spi_sensor_master.sim/step6"
    elif args.uart:
        BUILD = ROOT / "master/spi_sensor_master.sim/step7"
    elif args.top:
        BUILD = ROOT / ("master/spi_sensor_master.sim/step9" if args.impl else
                        "master/spi_sensor_master.sim/step8")
    elif args.i2c:
        BUILD = ROOT / "master/spi_sensor_master.sim/step10"
    BUILD.mkdir(parents=True, exist_ok=True)
    if not args.synth and not args.impl:
        if args.i2c:
            run("xvlog", I2C, TB.with_name("tb_i2c_master.v"))
            tests = [("tb_i2c_master", "I2C_MASTER_TEST_PASS")]
        elif args.top:
            run("xvlog", RTL, READER, FND, UART_TX, UART, RESET, TOP,
                TB.with_name("uart_rx_model.v"), TB.with_name("spi_sensor_peer.v"),
                TB.with_name("tb_reset_sync.v"), TB.with_name("tb_spi_sensor_master_top.v"))
            tests = [
                ("tb_reset_sync", "RESET_SYNC_TEST_PASS"),
                ("tb_spi_sensor_master_top", "MASTER_TOP_TEST_PASS"),
            ]
        elif args.uart:
            run("xvlog", RTL, READER, UART_TX, UART, TB.with_name("uart_rx_model.v"),
                TB.with_name("tb_uart_tx.v"), TB.with_name("tb_uart_reporter.v"),
                TB.with_name("spi_sensor_peer.v"), TB.with_name("tb_sensor_uart.v"))
            tests = [
                ("tb_uart_tx", "UART_TX_TEST_PASS"),
                ("tb_uart_reporter", "UART_REPORTER_TEST_PASS"),
                ("tb_sensor_uart", "SENSOR_UART_TEST_PASS"),
            ]
        elif args.fnd:
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
    if args.synth or args.impl:
        if args.i2c:
            rtl, top, marker = I2C, "i2c_master", "I2C_MASTER_SYNTH_PASS"
        elif args.top:
            rtl, top, marker = TOP, "spi_sensor_master_top", "MASTER_TOP_SYNTH_PASS"
        elif args.uart:
            rtl, top, marker = UART, "uart_reporter", "UART_SYNTH_PASS"
        elif args.fnd:
            rtl, top, marker = FND, "fnd_controller", "FND_SYNTH_PASS"
        elif args.sensor:
            rtl, top, marker = READER, "sensor_reader", "SENSOR_READER_SYNTH_PASS"
        else:
            rtl, top, marker = RTL, "spi_master", "SPI_SYNTH_PASS"
        expected_syncs = 8 if args.top else 4 if args.i2c else (
            0 if args.sensor or args.fnd or args.uart else 2
        )
        source_files = [RTL, READER, FND, UART_TX, UART, RESET, TOP] if args.top else (
            [UART_TX, rtl] if args.uart else [rtl]
        )
        read_sources = "".join(f"read_verilog {{{path.as_posix()}}}\n" for path in source_files)
        synthesis_mode = "" if args.top or args.i2c else " -mode out_of_context"
        constraints = f"read_xdc {{{XDC.as_posix()}}}\n" if args.top else (
            "create_clock -name sys_clk -period 10.0 [get_ports clk]\n"
        )
        top_checks = ""
        if args.top:
            top_checks = (
                "set pins {}\n"
                "foreach port [get_ports] {\n"
                "  set pin [get_property PACKAGE_PIN $port]\n"
                "  if {$pin eq {} || [get_property IOSTANDARD $port] ne {LVCMOS33}} {error {Unassigned board port}}\n"
                "  lappend pins $pin\n"
                "}\n"
                "if {[llength $pins] != 37 || [llength [lsort -unique $pins]] != 37} {error {Board pin count or duplicate mismatch}}\n"
                "report_drc -file drc_synth.rpt\n"
                "if {[llength [get_drc_violations -quiet]] != 0} {error {Board synthesis DRC violation}}\n"
                "report_cdc -file cdc_synth.rpt\n"
                "report_exceptions -file exceptions_synth.rpt\n"
                "report_timing -from [get_pins u_spi_master/miso_meta_reg/Q] -to [get_pins u_spi_master/miso_sync_reg/D] -file miso_sync_timing.rpt\n"
                "set sync_path [get_timing_paths -from [get_pins u_spi_master/miso_meta_reg/Q] -to [get_pins u_spi_master/miso_sync_reg/D] -max_paths 1]\n"
                "if {[llength $sync_path] != 1} {error {MISO internal synchronization path excluded}}\n"
                "foreach cell [get_cells {u_reset_sync/reset_meta_reg u_reset_sync/reset_synced_reg}] {\n"
                "  if {[get_property INIT $cell] ne {1'b1}} {error {Power-on reset initial state lost}}\n"
                "}\n"
            )
        implementation = ""
        if args.impl:
            marker = "MASTER_IMPL_PASS"
            implementation = (
                "opt_design\n"
                "place_design\n"
                "phys_opt_design\n"
                "route_design\n"
                "report_route_status -file route_status.rpt\n"
                "report_utilization -file utilization_route.rpt\n"
                "report_timing_summary -delay_type min_max -report_unconstrained -file timing_route.rpt\n"
                "foreach delay_type {max min} {\n"
                "  set path [get_timing_paths -delay_type $delay_type -max_paths 1]\n"
                "  if {[llength $path] == 0 || [get_property SLACK $path] < 0} {error {Routed internal timing target missed}}\n"
                "}\n"
                "report_drc -file drc_route.rpt\n"
                "if {[llength [get_drc_violations -quiet]] != 0} {error {Routed design DRC violation}}\n"
                "report_io -file io_route.rpt\n"
                "report_cdc -file cdc_route.rpt\n"
                "report_exceptions -file exceptions_route.rpt\n"
                "set syncs [get_cells -hier -quiet -filter {ASYNC_REG == TRUE}]\n"
                "if {[llength $syncs] != 8} {error {Routed synchronizers lost}}\n"
                "foreach cell [get_cells {u_reset_sync/reset_meta_reg u_reset_sync/reset_synced_reg}] {\n"
                "  if {[get_property INIT $cell] ne {1'b1}} {error {Routed reset initial state lost}}\n"
                "}\n"
                "report_timing -from [get_pins u_spi_master/miso_meta_reg/Q] -to [get_pins u_spi_master/miso_sync_reg/D] -file miso_sync_route.rpt\n"
                "set sync_path [get_timing_paths -from [get_pins u_spi_master/miso_meta_reg/Q] -to [get_pins u_spi_master/miso_sync_reg/D] -max_paths 1]\n"
                "if {[llength $sync_path] != 1} {error {Routed MISO synchronization path excluded}}\n"
                "write_checkpoint -force spi_sensor_master_routed.dcp\n"
                "write_bitstream -force spi_sensor_master.bit\n"
            )
        synth_script = BUILD / ("implement.tcl" if args.impl else "synth.tcl")
        synth_script.write_text(
            read_sources +
            f"synth_design -top {top} -part xc7a35tcpg236-1{synthesis_mode}\n" + constraints +
            "report_utilization -file utilization.rpt\n"
            "report_timing_summary -file timing_synth.rpt\n"
            "set critical [get_timing_paths -delay_type max -max_paths 1]\n"
            "if {[llength $critical] == 0} {error {Missing internal setup timing path}}\n"
            "if {[get_property SLACK $critical] < 0} {error {Internal setup timing target missed}}\n"
            "set latches [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]\n"
            "if {[llength $latches] != 0} {error {Unexpected inferred latch}}\n"
            "set syncs [get_cells -hier -quiet -filter {ASYNC_REG == TRUE}]\n"
            f"if {{[llength $syncs] != {expected_syncs}}} {{error {{Unexpected synchronizer count}}}}\n"
            + ("if {[llength [get_cells -hier -filter {REF_NAME == IOBUF}]] != 2} {error {Open-drain IOBUFs missing}}\n" if args.i2c else "")
            + top_checks + implementation +
            f"puts \"{marker} latches=[llength $latches] async_regs=[llength $syncs]\"\n"
            "exit 0\n", encoding="utf-8",
        )
        input_files = [*source_files, XDC, Path(__file__).resolve()] if args.impl else []
        input_hashes = {
            path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in input_files
        }
        if args.impl:
            (BUILD / "build_manifest.json").unlink(missing_ok=True)
        output = run("vivado", "-mode", "batch", "-nojournal", "-source", synth_script,
                     timeout=900 if args.impl else 180)
        if marker not in output:
            raise RuntimeError("synthesis checks did not finish")
        if args.impl:
            final_input_hashes = {
                path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in input_files
            }
            if final_input_hashes != input_hashes:
                raise RuntimeError("build inputs changed during implementation")
            route_text = (BUILD / "route_status.rpt").read_text(encoding="utf-8")
            route_counts = {
                name: int(value) for name, value in re.findall(
                    r"# of (routable nets|fully routed nets|nets with routing errors)\.+\s*:\s*(\d+)",
                    route_text,
                )
            }
            if (len(route_counts) != 3 or route_counts["routable nets"] == 0 or
                    route_counts["routable nets"] != route_counts["fully routed nets"] or
                    route_counts["nets with routing errors"] != 0):
                raise RuntimeError("implementation routing is incomplete")
            artifacts = [BUILD / "spi_sensor_master.bit", BUILD / "spi_sensor_master_routed.dcp"]
            if any(not path.is_file() or path.stat().st_size == 0 for path in artifacts):
                raise RuntimeError("implementation artifacts missing")
            manifest = {
                "status": "pass",
                "vivado": re.search(r"\*+ Vivado ([^\r\n]+)", output).group(1),
                "tool_build": re.search(r"SW Build ([^\r\n]+)", output).group(1),
                "part": "xc7a35tcpg236-1",
                "parameters": "RTL defaults",
                "command": "python scripts/verify_spi_master.py --top --impl",
                "external_spi_timing_verified": False,
                "hardware_programmed": False,
                "routing": route_counts,
                "inputs": input_hashes,
                "artifacts": {
                    path.name: {"bytes": path.stat().st_size,
                                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                    for path in artifacts
                },
            }
            (BUILD / "build_manifest.json").write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
    print(f"Verification complete. Generated files: {BUILD}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"Verification failed: {exc}", file=sys.stderr)
        sys.exit(1)
