# DREAD server image: itzg/minecraft-server with the pack baked in.
#
# The pack rides in the image rather than being downloaded at boot because DREAD publishes
# no server pack — there is nothing for AUTO_CURSEFORGE to fetch, and rebuilding the mod set
# from CurseForge at every restart would drift away from the jars the players actually have.
# The image tag IS the pack version.
#
# Built from the dist/ produced by build-pack.py:
#   python build-pack.py
#   docker build -t ghcr.io/isaacwallace123/dread-server:3.1.1 .
#
# java17 is the tag Minecraft 1.19.2 + Forge 43.x wants; newer JDKs break Forge's
# reflection into the module system on this version.
FROM itzg/minecraft-server:java17

# Unpacked over /data by GENERIC_PACKS on startup, in the order they are listed there.
# itzg checksums each archive and tracks the files it laid down, so a new image both applies
# the new pack and removes the previous revision's mods — without touching the world.
#
#   dread-server    the pack, a faithful copy of the client instance minus client-only mods
#   server-extras   server-only mods and config overrides; applied second, so it wins
COPY dist/dread-server.zip /packs/dread-server.zip
COPY dist/server-extras.zip /packs/server-extras.zip
