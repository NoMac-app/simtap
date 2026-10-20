// The CLI from source, as bin/simulator-use.js runs the built one: for tests that run it as a child process.
import { main } from "../../src/cli.ts";

process.exitCode = await main(process.argv.slice(2));
