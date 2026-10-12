# RASCL
Remotely Accessible Storage, Crafting, and Logistics

RASCL is a storage and auto-crafting solution for the CC: Tweaked mod in Minecraft. The program is currently a work-in-progress, but it currently features:

- A quick and easy to use interface for searching and requesting items stored across all connected storage containers
- The ability to view contents of each container without physically visiting it
- Methods for easily check which containers have a specific item, and how much of it the container has
- A container typing system that flags containers as either an input for importing items, as a storage container, or as an output for requested items
- An actively updated model of stored items reduces laggy peripheral calls
- A filter system that limits what items go into which storage containers based on item name, mod, attribute/tag, or a recursive, complex sequence of other filters
- All features accessible via remote clients that communicate via rednet (this includes pocket computers)

This project could not be possible without [Basalt2](https://github.com/Pyroxenium/Basalt2/tree/main) by NyoriE. This repo contains a pre-installed version of it that is compatible with my work, but please consider supporting the original project.

## Installation
To start off your storage network, run the following command in an _advanced_ computer (not an advanced pocket computer):

`wget run https://raw.githubusercontent.com/Sirc23/RASCL/main/install.lua`

Follow the prompts to download the files and configure the device. The `hostname` determines the rednet host that all communication is broadcast on; it should be unique to you and anyone you want to have access to your storage. The `device type` determines how the device should function within the network. See below for a list of types; your first installation should use `host`.

## Network Setup
All computers must have a wireless modem attached; all my development has been done using ender modems.

Computers can be set up with one of three device types:
- Host: Every network must have exactly one, and it must not be a pocket computer.
- Remote: These can be any advanced computer, pocket computer, or turtle. Remotes communicate with the host to wirelessly schedule requests, change a container's configuration, or just about anything else that you can do from a host's UI. Without other mods, these computers might not be very useful... but if you have a means of accessing even a single container from a distance, a remote pocket computer can become a way to wirelessly store and retrieve items from your entire storage system.
- Crafter: Currently, crafters do not do anything special since autocrafting is not implemented. These computers must be turtles with a crafting table attached to one side. They communicate with the host to schedule crafting tasks, but can also act like remotes in order to access the network as well. Eventually, you will be able to teach the system crafting recipes through these computers.

All storage containers on a network must be hooked up via wired modems. Storage containers will not be recognized if they are directly adjacent to the host computer. Each container should connect to the network exactly once; if multiple modems are connected to the same container, it will be recognized twice and the item counts will not accurately reflect the true values.

## Limitations
- The system tries to keep an internal model of the state of each container, but does not periodically check to see if its model is up-to-date with the real contents of the container. If an item is added or removed manually from the container without using input/output containers, the model will not detect it and will no longer be accurate. Until I introduce a background scanning process, please only import items through an input chest, and please only export items by requesting them in the interface.
- Containers placed directly next to the host computer are intentionally ignored due to the fact that the name of the peripheral differs from those discovered via wired modems.
- Theoretically, if your storage system is too large, it may be possible for the system to begin behaving unexpectedly. There are a couple algorithms that utilize the event queue which are not controlled or scheduled, so if they run at the same time they may exceed the 256 queue limit and events may be dropped. This should never happen with container content discovery / updating since I do have a scheduling system for that. For example, if you disconnect a huge chunk of the network all at once, the sheer number of peripheral detachment events may exceed 256 and some containers may not register as detached. Please report these problems if you notice them.
- RASCL relies heavily on touch capabilities, so you'll have a hard time doing anything without advanced computers. However, if you intend to only interact with the storage system via remotes, the host could likely be run on a normal computer.
- RASCL is intended to be run in terminals with default resolutions rather than on monitors. Still, if you intend to use monitors, the recommended minimum width is the same as the pocket computer, 26. The recommended minimum height is that of the turtle, 13.

## To-do List
- Autocrafting, including designating containers as inputs and outputs for external processing recipes
- Calculating fill level percents for individual containers, as well as combined fill level of all chests assigned to a filter
- Periodically scan containers for unauthorized changes in contents
- Palette editor, for customizability :)
- Probably some other scope creep stuff

## AI Usage and Philosophy
Two files in the project were AI-generated; `/classes/CSV.lua`, a class that manages CSV files, and the `installer.lua` used to install the program. All others were made by me. I believe that the tasks these two files accomplish are not related to the challenge of developing a storage system program. Any program that needs to store data to disk needs a few repetitive functions for reading and writing data; it's not interesting. Same with installing the program itself. If that's something that bothers you, please don't ask me to re-write them by hand. I still manually reviewed the files and changed them according to my needs; a manual rewrite would just waste my time achieving exactly the same results.

Beyond this, I have utilized AI to identify bugs, but only in circumstances where I have spent several hours attempting to resolve the issue manually and have made an honest effort to narrow down the cause. I have not used AI to implement the solutions to these problems (unless, of course, the solution ended up being a simple one-line typo, what can you do about that). In essence, I used AI as a code reviewing tool that can quickly find small mistakes and also explain deeply-seated bugs that transcend multiple classes. If that's something that bothers you, feel free to reach out and let me know.
