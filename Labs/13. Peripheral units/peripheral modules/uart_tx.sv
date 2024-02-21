// Copyright 2017 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// This file has been taken from https://github.com/pulp-platform/apb_uart_sv
// and modified by Andrei Solodovnikov in order to be used in
// Architectures of Processor Systems (APS) lab work project

// Changelog:
// some of the input signals has been hardcoded to constant values
// cfg_div_i input has been replaced by baudrate_i input signal.
// The signal cfg_div_i is now controled by baudrate_i input, and this control
// logic is work from assumption that clk_i is 10 MHz.

module uart_tx (
        input  logic            clk_i,
        input  logic            rst_i,
        output logic            tx_o,
        output logic            busy_o,
        input  logic [16:0]     baudrate_i,
        input  logic            parity_en_i,
        input  logic            stopbit_i,
        input  logic [7:0]      tx_data_i,
        input  logic            tx_valid_i
        //, input  logic            cfg_en_i,
        // input  logic [15:0]     cfg_div_i,
        // input  logic            cfg_parity_en_i,
        // input  logic [1:0]      cfg_bits_i,
        // input  logic            stopbit_i,
        // output logic            tx_ready_o
        );
    logic rstn_i;
    logic            cfg_en_i;
    logic [1:0]      cfg_bits_i;
    logic [15:0]     cfg_div_i;
    logic            tx_ready_o;
    assign rstn_i = !rst_i;
    assign cfg_en_i   = 1'b1;
    assign cfg_bits_i = 2'd3;
    always_comb begin
        case(baudrate_i)
            17'd9600  : cfg_div_i = 15'd1041;
            17'd19200 : cfg_div_i = 15'd520;
            17'd38400 : cfg_div_i = 15'd259;
            17'd57600 : cfg_div_i = 15'd173;
            17'd115200: cfg_div_i = 15'd86;
            default   : cfg_div_i = 15'd1041;
        endcase
    end
    enum logic [2:0] {IDLE,START_BIT,DATA,PARITY,STOP_BIT_FIRST,STOP_BIT_LAST} CS,NS;

    logic [7:0]  reg_data;
    logic [7:0]  reg_data_next;


    logic [2:0]  reg_bit_count;
    logic [2:0]  reg_bit_count_next;

    logic [2:0]  s_target_bits;

    logic        parity_bit;
    logic        parity_bit_next;

    logic        sampleData;

    logic [15:0] baud_cnt;
    logic        baudgen_en;
    logic        bit_done;

    assign busy_o = (CS != IDLE);

    always_comb
    begin
        case(cfg_bits_i)
            2'b00:
                s_target_bits = 3'h4;
            2'b01:
                s_target_bits = 3'h5;
            2'b10:
                s_target_bits = 3'h6;
            2'b11:
                s_target_bits = 3'h7;
        endcase
    end

    always_comb
    begin
        NS = CS;
        tx_o = 1'b1;
        sampleData = 1'b0;
        reg_bit_count_next  = reg_bit_count;
        reg_data_next = {1'b1,reg_data[7:1]};
        tx_ready_o = 1'b0;
        baudgen_en = 1'b0;
        parity_bit_next = parity_bit;
        case(CS)
            IDLE:
            begin
                if (cfg_en_i)
                    tx_ready_o = 1'b1;
                if (tx_valid_i)
                begin
                    NS = START_BIT;
                    sampleData = 1'b1;
                    reg_data_next = tx_data_i;
                end
            end

            START_BIT:
            begin
                tx_o = 1'b0;
                parity_bit_next = 1'b0;
                baudgen_en = 1'b1;
                if (bit_done)
                    NS = DATA;
            end

            DATA:
            begin
                tx_o = reg_data[0];
                baudgen_en = 1'b1;
                parity_bit_next = parity_bit ^ reg_data[0];
                if (bit_done)
                begin
                    if (reg_bit_count == s_target_bits)
                    begin
                        reg_bit_count_next = 'h0;
                        if (parity_en_i)
                        begin
                            NS = PARITY;
                        end
                        else
                        begin
                            NS = STOP_BIT_FIRST;
                        end
                    end
                    else
                    begin
                        reg_bit_count_next = reg_bit_count + 1;
                        sampleData = 1'b1;
                    end
                end
            end

            PARITY:
            begin
                tx_o = parity_bit;
                baudgen_en = 1'b1;
                if (bit_done)
                    NS = STOP_BIT_FIRST;
            end
            STOP_BIT_FIRST:
            begin
                tx_o = 1'b1;
                baudgen_en = 1'b1;
                if (bit_done)
                begin
                    if (stopbit_i)
                        NS = STOP_BIT_LAST;
                    else
                        NS = IDLE;
                end
            end
            STOP_BIT_LAST:
            begin
                tx_o = 1'b1;
                baudgen_en = 1'b1;
                if (bit_done)
                begin
                    NS = IDLE;
                end
            end
            default:
                NS = IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rstn_i)
    begin
        if (rstn_i == 1'b0)
        begin
            CS             <= IDLE;
            reg_data       <= 8'hFF;
            reg_bit_count  <=  'h0;
            parity_bit     <= 1'b0;
        end
        else
        begin
            if(bit_done)
            begin
                parity_bit <= parity_bit_next;
            end

            if(sampleData)
            begin
                reg_data <= reg_data_next;
            end

            reg_bit_count  <= reg_bit_count_next;
            if(cfg_en_i)
               CS <= NS;
            else
               CS <= IDLE;
        end
    end

    always_ff @(posedge clk_i or negedge rstn_i)
    begin
        if (rstn_i == 1'b0)
        begin
            baud_cnt <= 'h0;
            bit_done <= 1'b0;
        end
        else
        begin
            if(baudgen_en)
            begin
                if(baud_cnt == cfg_div_i)
                begin
                    baud_cnt <= 'h0;
                    bit_done <= 1'b1;
                end
                else
                begin
                    baud_cnt <= baud_cnt + 1;
                    bit_done <= 1'b0;
                end
            end
            else
            begin
                baud_cnt <= 'h0;
                bit_done <= 1'b0;
            end
        end
    end

endmodule