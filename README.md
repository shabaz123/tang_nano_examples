# Tang Nano VHDL Examples

## double_blinky
This project blinks two LEDs alternately. Tested on Tang Nano 9k.

See [FPGA for Beginners Part 2 - Double Blinky, a VHDL walk-through](https://community.element14.com/technologies/fpga-group/b/blog/posts/tang-nano-series-and-gowin-fpgas-for-beginners-part-2-double-blinky-a-vhdl-walk-through)

## uart_loopback
This project implements a UART (115200) that writes back the received byte. 

This project was tested on Tang Nano 9k (the UART pins are connected to the USB-UART on the Tang nano 9k board). To test the project, use Windows Device Manager to see what COM port there is, then go into the python_test folder and type (replace nn with the actual COM port number): 

```python ./test_loopback.py COMnn```

If it works, you'll see:

```PASS: 531 bytes echoed exactly at 115200 baud```

## psram_uart
This project implements the ability to upload and download content to/from PSRAM, using the UART. Tested on Tang Nano 9k.

The project configures the FPGA PSRAM to be in two channels, both 32Mbit in size.

To run the demo, type the following, which attempts to write to channel 1 (the choice is channel 0 or channel 1) 100 bursts of data (each burst is 32 bytes, so that is 3200 bytes total) from an example file called output.bin:

```python .\python_test\upload_verify.py COM18 .\python_test\output.bin --channel 1 --limit-bursts 100```

The above will write a 'burst' of 32 bytes, then immediately read it back, and repeat with another chunk of data, for a total of 100 times. If successful you'll see:

```
Verified 1/100 bursts
Verified 100/100 bursts
PASS: 3200 PSRAM bytes written/read back exactly; original BIN length 192000 bytes, channel 1
```

To transfer the entire demo file (19200 bytes):

```python .\python_test\upload_verify.py COM18 .\python_test\output.bin --channel 0 ```

If successful the result will be:

```
Verified 5889/6000 bursts
Verified 6000/6000 bursts
PASS: 192000 PSRAM bytes written/read back exactly; original BIN length 192000 bytes, channel 0
```
The way the transfers work, is that a header is sent first, then 32 bytes. See the Python file function called *transaction* for deciphering this.




