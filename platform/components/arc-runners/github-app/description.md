## ⚡ Blockout Runners

**Our own CI muscle, living in the Blockout homelab.** 📦

When a BlockoutGames repository queues a workflow with `runs-on: blockout`, this app lets our
Actions Runner Controller spin up a fresh runner just for that job, run the checks, and vanish
again. No minutes billed, no leftovers, no waiting on someone else's machines.

- 🧹 **Clean every time.** One brand-new pod per job, gone the moment it finishes.
- 💤 **Sleeps when idle.** Zero runners until there's work to do.
- 🔒 **Asks for one thing.** Self-hosted runners, read and write. Nothing else.

*Built by Blockout Games. Click, build, ship.* 🎮
