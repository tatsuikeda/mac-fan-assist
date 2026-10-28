# Mac Fan Assist

Multi-sensor fan control for Intel MacBook Pros with the T2 chip. It is built and tested on a 16-inch 2019 MacBook Pro (MacBookPro16,1, i7-9750H, Radeon Pro 5500M) running macOS Sequoia 15.8.2.

Apple's fan control mostly watches the CPU and reacts slowly. Fan apps like Macs Fan Control let you base a curve on one sensor. On this machine, the parts that get hot are the CPU, the Radeon GPU, the heatpipe and the **battery**, and they don't heat up together. `fanassist` watches all four, works out which one is closest to its limit, and ramps both fans early. It never sets a fan below what macOS asks for, and it always hands the fans back to macOS when things cool down or when it stops.

This README is also the story of how I got here, because most of what I tried first didn't work. If you own one of these Macs, the dead ends may save you a weekend.

## The short version

- **Clean the fans and replace the thermal paste first.** No software fixes a heatsink that isn't touching the chip.
- **Full turbo can't be sustained on this chassis.** At about 66 W the CPU goes from 78°C to 95°C in 8 seconds, however fast the fans spin. The limit is how fast heat leaves the chip, not airflow.
- **What software *can* do** is react early to the parts Apple's fan curve ignores. That keeps the battery and GPU cooler and stops sustained medium loads (exports, builds) from creeping into throttling.
- **Kernel extensions that cap turbo or undervolt don't load on modern macOS** without turning off System Integrity Protection. I didn't go there.

## The journey

### 1. Dirty fans and dried-out paste

The Mac ran hot and loud for years. When it was opened, the fans were filthy and the factory thermal paste had dried into something like paint chips. I cleaned the fans and replaced the paste with a **Honeywell PTM7950** phase-change pad. It's a sheet that melts into the gaps at operating temperature and doesn't pump out or dry out the way paste does.

If you're doing this yourself, iFixit's teardown of this model shows how it comes apart: [MacBook Pro 16" 2019 Teardown](https://www.ifixit.com/Teardown/MacBook+Pro+16-Inch+2019+Teardown/128106). iFixit rates it 1 out of 10 for repairability. The CPU and GPU share one heatsink and heatpipe assembly, which turns out to matter a lot (see section 5).

The repaste helped, but this chassis still can't shed a sustained full-turbo load. Everything after this is about living within that limit.

### 2. What Low Power Mode actually does on an Intel Mac

On this Mac, Low Power Mode turns Turbo Boost off. The CPU runs at a flat 2.6 GHz and draws about 20 to 27 W. With turbo on, it runs 4.0 GHz on all cores (4.5 GHz on one or two) at about 66 to 70 W.

There's nothing in between. macOS has no "medium" power setting for Intel Macs, so it's 27 W or 66 W.

### 3. Dead ends: kernel extensions

Tools that cap turbo or undervolt the CPU all need a kernel extension:

| Tool | What it does | Why it didn't work |
|---|---|---|
| Turbo Boost Switcher | Turns turbo off and on | Its kernel extension is unsigned and won't load with System Integrity Protection on. |
| VoltageShift, Volta | Undervolt or set power limits | Same problem: they need SIP's kext protection turned off. |
| CPUTune, chill | Power and frequency limits | Same. |

Signing a kernel extension yourself isn't realistic either: it needs a special entitlement from Apple, which is rarely granted. Turning SIP off for the life of the machine wasn't a trade I wanted to make. And kernel extensions are on their way out on macOS anyway.

### 4. Dead end: a CPU-only fan curve

My next idea was a custom curve in Macs Fan Control: start the fans at a CPU temperature of 60°C and run them flat out at 85°C. It made things worse.

Under load the CPU sat at a comfortable 65°C, but macOS raised thermal pressure anyway. The CPU speed limit (`pmset -g therm`) dropped to **22%** and the CPU was pinned at **800 MHz**. Something other than the CPU was hot, and the curve didn't see it. The battery was at about 47°C. Setting the fans back to Auto ran them to 5,600 rpm and cleared it in about five minutes.

The lesson: on this Mac, macOS throttles for heat it can see in many places. If your fan curve watches only the CPU, it can quietly fight macOS.

### 5. Finding out what actually heats up

`stress-sensors` loads all 12 CPU threads and records every SMC temperature sensor every couple of seconds. This is the first run, with fans on Auto and no fan helper, ranked by how much each sensor rose:

| Sensor | SMC key | Idle | Peak | Rise |
|---|---|---|---|---|
| Radeon GPU | TGDD | 35.0 | 79.0 | **+44.0** |
| Hottest CPU core | TC1C | 54.0 | 93.0 | +39.0 |
| CPU (filtered) | TC0F | 55.9 | 93.9 | +38.0 |
| Heatpipe 2 | Th1H | 42.2 | 73.7 | +31.5 |
| Thunderbolt (right) | TTRD | 34.7 | 64.4 | +29.7 |
| Battery (all three) | TB0T/1T/2T | 38.3 | **54.3** | +16.0 |

All temperatures are in °C. Three things stood out:

1. **The Radeon GPU heated up more than anything else, though the test didn't use it.** It shares the heatpipes with the CPU, so CPU heat soaks into it.
2. **The battery reached 54°C.** Lithium-ion batteries age faster when they're hot, and nothing cools the battery directly.
3. **Apple's fans were slow to react.** They sat near their 1,800 rpm minimum for the first 2.5 minutes, while the cores were at 83°C. They reached about 4,700 rpm only near the end, when temperatures were already falling.

Note: in this run, Low Power Mode switched on 24 seconds in (see `autopower` below), so most of it ran at about 27 W. At sustained full power the GPU and battery would get hotter still.

### 6. The hard limit

With turbo on, I ran the same load three ways:

| Fans | Power | Result |
|---|---|---|
| Apple Auto | 70 to 74 W | 69°C to 91°C in 8 seconds |
| Apple Auto | 65 to 70 W | 63°C to 97.7°C in 16 seconds; fans had only reached 2,900 rpm |
| Full speed (about 5,600 rpm) | 64 to 69 W | Reached 95°C in 25 seconds, then crept up to 97°C, where I stopped it at 50 seconds |

Even at full speed, the fans only hold the CPU just under its 100°C limit. When left alone at 91°C, macOS cut package power from about 70 W to about 30 W on its own, and the CPU cooled to 76°C.

So the answer to "can I run full turbo without throttling?" on this machine is no. Bursts are fine. Sustained full turbo isn't.

### 7. What I ended up with

- **`fanassist`** watches the CPU, GPU, heatpipe and battery, and ramps the fans as soon as any of them warms up, instead of waiting for the CPU. In the same stress test it had both fans at about 4,600 rpm within 8 seconds, where Apple's curve took minutes. (That run hit 95°C at full turbo after 8 seconds and stopped, so it shows how fast fanassist reacts, not how much cooler it keeps things over a long load.)
- **`autopower`** (optional) keeps Low Power Mode off so short bursts are snappy, and switches it on when the CPU stays at 90°C or above for 6 seconds. It switches Low Power Mode off again after a minute at 75°C or below.
- **`export-guard`** runs one heavy job or app at full speed and pauses it whenever the CPU reaches 92°C, resuming at 85°C.

## How fanassist works

Every 2 seconds, `fanassist` reads these sensors and works out a "demand" for each, from 0 (cool) to 1 (at its limit):

| Part | SMC keys | Demand starts at | Full fans at |
|---|---|---|---|
| CPU | TC0F | 78°C | 94°C |
| Radeon GPU | TGDD | 70°C | 88°C |
| Heatpipe | Th1H | 68°C | 80°C |
| Battery | TB0T, TB1T, TB2T (hottest) | 44°C | 50°C |

It takes the highest demand and sets both fans to that fraction of their range. On this Mac, fan 1 runs 1,836 to 5,616 rpm and fan 2 runs 1,700 to 5,200 rpm.

Safety rules:

- **Never below macOS.** When it takes over, it records the speed macOS was asking for and never goes below it.
- **Smooth slow-downs.** Speeds go up immediately but come down at most 250 rpm every 2 seconds, so the fans don't surge.
- **Hands back to Auto** after 30 seconds of everything being cool.
- **Hands back to Auto on exit,** however it stops (uninstall, crash, `launchctl bootout`). If it crashes, launchd restarts it within 30 seconds.

To tune it, edit the `RAMPS` block at the top of `bin/fanassist` and rerun `./install.sh`.

It controls the fans with the `smc` command-line tool from [smcFanControl](https://github.com/hholtmann/smcFanControl). It puts each fan in forced mode (`F0Md`/`F1Md` = 1) and sets a target speed (`F0Tg`/`F1Tg`, a float). On this T2 Mac that works directly; no extra unlock key is needed.

### Why not just use Macs Fan Control?

Macs Fan Control is a good app, and I still use it to *see* fan speeds. But it bases each fan's curve on one sensor. On this Mac no single sensor tells the whole story, and the CPU-only curve in section 4 caused throttling. Keep it on **Auto** for both fans if you run `fanassist`: only one program should ever set the fans, or they'll fight every couple of seconds.

## Install

Needs an Intel Mac with two fans, the Xcode Command Line Tools (`xcode-select --install`), and an admin account.

```bash
git clone https://github.com/tatsuikeda/mac-fan-assist.git
cd mac-fan-assist
./install.sh                      # fanassist, plus the export-guard and stress-sensors tools
./install.sh --with-autopower     # also run autopower
./install.sh --with-smclog        # also log every temperature every 30 s (needs iSMC, below)
```

The installer:

1. Downloads smcFanControl at a fixed commit and builds its `smc` tool on your Mac. The repo doesn't ship a binary.
2. Checks that your Mac has every SMC key `fanassist` uses, and stops if it doesn't.
3. Installs the background services as root LaunchDaemons.

Logs are in `/Library/Logs/fanassist.log` and `/Library/Logs/autopower.log`.

To remove everything and put the fans back on Auto:

```bash
./uninstall.sh
```

### Optional: iSMC

`stress-sensors` and `smclog` use [iSMC](https://github.com/dkorunic/iSMC) to read every sensor with its name:

```bash
brew install dkorunic/tap/ismc
```

### export-guard and passwordless sudo

`export-guard` reads the CPU temperature with `powermetrics` and switches Low Power Mode with `pmset`, both of which need root. To let it run without a password prompt, add a narrow sudoers rule with `sudo visudo -f /etc/sudoers.d/mac-fan-assist`:

```
%admin ALL=(root) NOPASSWD: /usr/bin/powermetrics, /usr/bin/pmset
```

Then:

```bash
export-guard -a Lightroom          # guard a running app by name (start the export first)
export-guard -p 12345              # guard any process and its children
export-guard -- make -j12          # run a command under the guard
```

If `autopower` is running, `export-guard` leaves Low Power Mode to it and only pauses and resumes the work.

### stress-sensors

```bash
stress-sensors 300 ~/stress.jsonl
```

This runs 12 busy threads for up to 300 seconds (stopping early if any core reaches 95°C), then records 90 seconds of cooldown. At the end it prints every sensor ranked by how much it rose. Plug in to AC power first.

## Other Macs

This is tested only on a MacBookPro16,1. Other Intel MacBook Pros with a T2 chip (2018 to 2020) will probably work, but sensor keys differ between models, especially for the GPU. The installer refuses to run on another model unless you pass `--force`, and it still checks every key.

To adapt it, run `iSMC temp` to list your Mac's sensors, then edit the `RAMPS` block in `bin/fanassist`. Apple silicon Macs aren't supported, and don't need this.

## Risks

This writes to your Mac's System Management Controller. Here is what's in place to limit the risk:

- It only ever raises the fans above what macOS asks for.
- It hands control back to macOS whenever it stops.
- It never touches CPU power, voltage or frequency.
- The programs that run as root live in `/Library/PrivilegedHelperTools/mac-fan-assist`. The installer refuses to continue unless that folder, and every folder above it, is owned by root and writable only by root, so nothing running as your user can swap them out.
- `autopower` and `export-guard` only use Apple's own `pmset` and `powermetrics`.

That said, this is a hobby project tested on one machine. Use it at your own risk.

## License

MIT, see [LICENSE](LICENSE). The `smc` tool that the installer builds belongs to smcFanControl and is licensed under the GPL v2. It is downloaded and built on your Mac, not distributed here.
