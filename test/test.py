import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles


outputs = [ 0x41, 0x42, 0x49, 0x99, 0xcc, 0xcc, 0x99, 0x55, 0x55, 0x00,	
	    0x77, 0x11, 0x66, 0x01, 0x02, 4,    7,    0x99, 0x55, 0x99,
	    0x55, 0x9a, 0x55, 0,    2,    0,    4,    0,    6,    0,
	    8,    0,    10,   0,    12,   0xfe, 0xff, 0xfe, 0x7f, 0xfa,
	    0xff, 24,   0,    0,    0,    1,    0,    0xfe, 0xff, 0,
	    0,    0,    0,    0x15, 0,    0x14, 0,    0x84, 0,    0x19,
	    0x84, 0x1a, 0x1b, 0x84, 0,    0,    0,    0x3,  0x7,  0x8c,
	    0xdf, 0xff, 0xdf, 0x00, 16,   8,    0x00, 0xff, 0x00, 0x80,
	    0x00, 0x7f, 0x65, 3,    0x65, 0xaa, 0x04, 0x06, 0x10, 0x66,
	    0x55, 0xc4, 0x33, 0xc4, 0xff, 0x77, 0x77, 0x33, 0x77, 0x00,
	    0x00, 0x77, 0x67, 0,    0,    3,    6,    0,    2,    0,
	    0x54, 0x55, 2,    0,    0,    0,    2,    0,    0x54, 0x55,
	    0,    0x34, 0,    0x40, 0x12, 0,    1,    0,    0x12, 0,
	    1,    0,    0x92, 0xff, 0xf9, 0xff, 0,    0,    0xff, 0xff,
	    0x23, 1,    0x23, 1,    3,    0x8e, 1,    0,    7,    8, 
	    9,    8,    0,    6,    4,    229,  0x85, 0x5a, 0x23, 0x9a,
	    0x53, 0x55, 0x76, 2,    3,    4,    5,    123,  0xfe, 0,
	    0,    1,    1,    0,    0xff, 0xff, 0xaa,
0xffaa]

@cocotb.test()
async def test_vc_cpu(dut):
    dut._log.info("start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # reset
    dut._log.info("reset")
    # reset
    dut.rst_n.value = 0
    # set a different compare value
    #dut.ui_in.value = 3
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # check all values
    for i in range(177):
        dut._log.info("check output {}".format(i))
        dut._log.info("expected value {}".format(outputs[i]))
        while 1 :
            await ClockCycles(dut.clk, 1)
            if int(dut.uart_done) == 1:
                dut._log.info("read value {}".format(int(dut.c)))
                assert int(dut.c) == outputs[i]
                break
