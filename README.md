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



