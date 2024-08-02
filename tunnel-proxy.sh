#!/bin/sh

ssh -D 8090 -q -C -N -i /Users/<your-user>/.ssh/id_ed25519 <user>@<server-address>
