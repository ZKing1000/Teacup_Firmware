#!/bin/bash

# This should point to a SIMINFO-enabled SimulAVR executable:
SIMULAVR="../../simulavr/src/simulavr"
if [ ! -x "${SIMULAVR}" ]; then
  echo "SimulAVR executable not found, please adjust"
  echo "variables at the top of ${0}."
  exit 1;
fi


# Prepare a pin tracing file, assuming a Gen7-v1.4 configuration. See
# http://reprap.org/wiki/SimulAVR#Putting_things_together:_an_example
echo "# X Dir"              > /tmp/tracein.txt
echo "+ PORTA.A3-Out"      >> /tmp/tracein.txt
echo "# X Step"            >> /tmp/tracein.txt
echo "+ PORTA.A2-Out"      >> /tmp/tracein.txt
echo "# Y Dir"             >> /tmp/tracein.txt
echo "+ PORTA.A5-Out"      >> /tmp/tracein.txt
echo "# Y Step"            >> /tmp/tracein.txt
echo "+ PORTA.A4-Out"      >> /tmp/tracein.txt


for GCODE_FILE in "triangle.gcode" "straight-speeds.gcode"; do

  FILE="${GCODE_FILE%.gcode}"
  VCD_FILE="${FILE}.vcd"
  

  # We assume here queue and rx buffer are large enough to read
  # the file in one chunk. If not, raise MOVEBUFFER_SIZE in config.h.
  "${SIMULAVR}" -c vcd:/tmp/tracein.txt:"${VCD_FILE}" \
                -f ../build/teacup.elf \
                -m 60000000000  < "${GCODE_FILE}"


  # Make plottable files from VCD files.
  # This is very rudimentary and does a lot of assumptions.
  # For examble, pin data is assumed to always be b0/b1, pin naming
  # is assumed to match the order in tracein.txt and starting at "0".
  awk '
    BEGIN {
      dataFile = "'"${FILE}"'.data";
      print "0 0 0 0 0" > dataFile;
      xDir = yDir = 0;
      xPos = yPos = 0;
      xVel = yVel = 0;
      yAcc = yAcc = 0;
      lastxTime = lastyTime = 0;
    }
    /^#/ {
      time = substr($0, 2);
      next;
    }
    {
      bit = substr($1, 2);
      if ($2 == "0") { # X Dir
        if (bit == 0) xDir = -1;
        else if (bit == 1) xDir = 1;
        else xDir = 0;
      }
      if ($2 == "2") { # Y Dir
        if (bit == 0) yDir = -1;
        else if (bit == 1) yDir = 1;
        else yDir = 0;
      }
      if ($2 == "1") { # X Step, count only raising flanges
        if (bit == 1) {
          xPos += xDir;
          xVel = 1000000000 / (time - lastxTime);
          print time " " xPos " " yPos " " xVel " " yVel >> dataFile;
          lastxTime = time;
        }
      }
      if ($2 == "3") { # Y Step, count only raising flanges
        if (bit == 1) {
          yPos += yDir;
          yVel = 1000000000 / (time - lastyTime);
          print time " " xPos " " yPos " " xVel " " yVel >> dataFile;
          lastyTime = time;
        }
      }
    }
  ' < "${VCD_FILE}"


  # Finally, create a plot.
  gnuplot << EOF
    set terminal png size 1024,768
    set output "${FILE}.png"

    set title "${GCODE_FILE}"

    set xlabel "X steps"
    set ylabel "Y steps"
    set y2label "feedrate [steps/s]"

    #set origin 10,10;
    plot "${FILE}.data" using (\$2):(\$3) with dots title "position", \
         "${FILE}.data" using (\$2):(\$4) with dots title "X feedrate", \
         "${FILE}.data" using (\$2):(\$5) with dots title "Y feedrate"
EOF

  display "${FILE}.png" &

done
