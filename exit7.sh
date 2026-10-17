#!/bin/bash
read -r pp < /proc/$$/ppid; echo "before exit, ppid $pp"
exit 7
