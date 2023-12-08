.data
plaintext_fp: .asciz "data/plaintext.txt"
encrypted_fp: .asciz "data/encrypted.txt"
decrypted_fp: .asciz "data/decrypted.txt"
compare_msg:  .ascii "Compare returned: "
compare_val:  .asciz " "

.align 2
password:    .byte  'd' 'e' 'l' 's'
mod_pass:    .space 8
char_buffer: .space 8
.text

MAIN:
    jal   x1, INIT

    la    a5, plaintext_fp
    la    a6, encrypted_fp
    jal   x1, ENCRYPT

    la    a5, encrypted_fp
    la    a6, decrypted_fp
    jal   x1, DECRYPT

    la    a5, plaintext_fp
    la    a6, decrypted_fp
    jal   x1, COMPARE
    addi  t1, a0, 0x30      # convert binary 0/1 to char
    la    t2, compare_val   # &compare_val
    sb    t1, 0(t2)
    
    li    a7, 55            # 'MESSAGE DIALOG' ID
    la    a0, compare_msg   # &compare_msg
    li    a1, 1             # information message
    ecall

    b     EXIT

#===============================================================================#
# INIT: Saves common addresses in registers, modifies password chars
#===============================================================================#
INIT:
    la    s2, mod_pass      # save address of modified password chars
    la    s3, char_buffer   # save address of I/O buffer

    # GENERATE MODIFIED PASS CHARS (ZERO {0,4} BITS)

    lw    t1, password      # t1 = password
    li    t2, 0xEEEEEEEE    # bitmask
    and   t1, t1, t2        # clear bits 0 and 4 of each byte in password
    sw    t1, 0(s2)         # s2[0:4] = modified pass chars

    # GENERATE MODIFIED PASS CHARS (ZERO {0,4} BITS) WITH REVERSED NIBBLES

    li    t2, 0x0F0F0F0F    # bitmask
    and   t3, t1, t2        # t3 holds every other first nibble
    slli  t2, t2, 4         # shift mask
    and   t4, t1, t2        # t4 hold every other second nibble
    slli  t3, t3, 4         # shift B's left
    srli  t4, t4, 4         # shift A's right
    or    t1, t3, t4        # t1 holds reversed nibbles for each byte
    sw    t1, 4(s2)         # store reverse-nibble modified pass chars

    jalr  x0, 0(x1)         # return to caller

#===============================================================================#
# ENCRYPT: Converts plaintext file into ciphertext file
#    -> a5 : &input_path
#    -> a6 : &output_path
#===============================================================================#
ENCRYPT:
    # OPEN THE INPUT FILE AND SAVE FILE DESCRIPTOR IN S5 IN READ MODE

    li    a7, 1024          # 'OPEN FILE' ID
    mv    a0, a5            # &plaintext_fp
    li    a1, 0             # permission: O_RDONLY
    ecall                   # returns fd in a0
    blt   a0, x0, ERROR     # exit with error if open fails
    mv    s5, a0            # save fd

    # OPEN THE OUTPUT FILE AND SAVE FILE DESCRIPTOR IN S6 IN WRITE MODE

    li    a7, 1024          # 'OPEN FILE' ID
    mv    a0, a6            # &encrypted_fp
    li    a1, 1             # permission: O_WRONLY | O_CREATE
    ecall                   # returns fd in a0
    blt   a0, x0, ERROR     # exit with error if open fails
    mv    s6, a0            # save fd

  LOOPA:
    # READ FOUR CHARACTERS FROM PLAINTEXT

    li    a7, 63            # 'READ FILE' ID
    mv    a0, s5            # fd for plaintext.txt
    la    a1, char_buffer   # input buffer
    li    a2, 4             # number of chars to read
    ecall                   # returns number of bytes read in a0
    beq   a0, x0, EXITA     # break if EOF
    blt   a0, x0, ERROR     # exit with error if read fails
    mv    s7, a0            # save the number of chars read

    # DETERMINE WHICH NIBBLES NEED TO BE SWAPPED

    lw    t1, char_buffer   # get plaintext word
    li    t2, 0x01010101    # bitmask for 0th bits
    li    t3, 0x10101010    # bitmask for 4th bits
    and   t2, t1, t2        # isolate 0th bits
    and   t3, t1, t3        # isolate 4th bits
    srli  t3, t3, 4         # move 4th bits into 0th position
    xor   t2, t2, t3        # every 0th bit is (0 = same, 1 = different)
    li    s1, 0             # empty register for final password word

    li    t3, 0             # int i=0
    li    t4, 4             # int n=4
  LOOPB:
    bge   t3, t4, EXITB     # while(i<n)

    slli  s1, s1, 8         # shift s1 to make room for next char
    add   t6, s2, t3        # t6 = &modpass[i]
    and   t5, t2, t3        # isolate lower bit (0 = sub, 1 = skip)
    bne   t5, x0, CONTB     # skip swapping if 1
    addi  t6, t6, 4         # offset into reverse nibbles if 0

  CONTB:
    lb    a0, 0(t6)         # a0 = either modpass[i] or modpass[i+4]
    add   s1, s1, a0        # add pass char to s1
    addi  t3, t3, 1         # i++
    b     LOOPB             # next B

  EXITB:
    xor   s1, s1, t1        # XOR password with plaintext
    sw    s1, 0(s3)         # store encrypted text in buffer

    # WRITE THE BUFFER TO CIPHERTEXT

    li    a7, 64            # 'WRITE FILE' ID
    mv    a0, s6            # &ciphertext
    la    a1, char_buffer   # &char_buffer
    mv    a2, s7            # num chars to write (=num chars read)
    ecall                   # write to file      

    b     LOOPA             # next A

  EXITA:

    # CLOSE FILESTREAMS

    li    a7, 57            # 'CLOSE FILE' ID
    mv    a0, s5            # load fd
    ecall                   # close input
    blt   a0, x0, ERROR     # exit with error if close fails
    mv    a0, s6            # load fd
    ecall                   # close output (flush)
    blt   a0, x0, ERROR     # exit with error if close fails

    jalr  x0, 0(x1)         # return to caller

#===============================================================================#
# DECRYPT: Converts ciphertext file into decrypted file
#    -> a5 : &input_path
#    -> a6 : &output_path
#===============================================================================#
DECRYPT:
    addi  sp, sp, -4        # allocate stack space for x1
    sw    x1, 0(sp)         # push x1 onto stack
    jal   x1, ENCRYPT       # symmetric algorithm, so use encrypt to decrypt
    lw    x1, 0(sp)         # restore x1
    addi  sp, sp, 4         # pop stack

    jalr  x0, 0(x1)         # return to caller

#===============================================================================#
# COMPARE: Determines if two files match exactly
#    -> a5 : &file1_path
#    -> a6 : &file2_path
#    <- a0 : 0x0 if files don't match, 0x1 if they do
#===============================================================================#
COMPARE:
    # OPEN FILE 1 AND SAVE FILE DESCRIPTOR IN S5

    li    a7, 1024          # 'OPEN FILE' ID
    mv    a0, a5            # &plaintext_fp
    li    a1, 0             # permission: O_RDONLY
    ecall                   # returns fd in a0
    blt   a0, x0, ERROR     # exit with error if open fails
    mv    s5, a0            # save fd

    # OPEN FILE 2 AND SAVE FILE DESCRIPTOR IN S6

    li    a7, 1024          # 'OPEN FILE' ID
    mv    a0, a6            # &decrypted_fp
    li    a1, 0             # permission: O_RDONLY
    ecall                   # returns fd in a0
    blt   a0, x0, ERROR     # exit with error if open fails
    mv    s6, a0            # save fd

    li    t5, 1             # Nonzero init for loop
  LOOPC:
    add   t5, t5, t6        # total number of reads from both files
    beq   t5, x0, EXITC     # if neither file has anything left

    # READ FOUR CHARACTERS FROM PLAINTEXT

    li    a7, 63            # 'READ FILE' ID
    mv    a0, s5            # fd for plaintext.txt
    la    a1, char_buffer   # input buffer
    li    a2, 4             # number of chars to read
    ecall                   # returns number of bytes read in a0
    blt   a0, x0, ERROR     # exit with error if read fails
    mv    t5, a0            # save return value for loop
    lw    t1, 0(a1)         # save plaintext word

    # READ FOUR CHARACTERS FROM DECRYPTED

    li    a7, 63            # 'READ FILE' ID
    mv    a0, s6            # fd for decrypted.txt
    la    a1, char_buffer   # input buffer
    addi  a1, a1, 4         # offset buffer to not overwrite
    li    a2, 4             # number of chars to read
    ecall                   # returns number of bytes read in a0
    blt   a0, x0, ERROR     # exit with error if read fails
    mv    t6, a0            # save return value for loop
    lw    t2, 0(a1)         # save decrypted word

    # CHECK FOR DIFFERENCES

    xor   t1, t1, t2        # t1 = (plaintext == decrypted) ? 0 : 1
    bne   t1, x0, NOTEQ     # branch if difference detected
    b     LOOPC             # next C

  EXITC:
    li    a0, 1             # return value 1 (files equal)
    jalr  x0, 0(x1)         # return to caller
  
  NOTEQ:
    li    a0, 0             # return value 0 (file differ)
    jalr  x0, 0(x1)         # return to caller

#===============================================================================#
# ERROR: Terminates program with error code
#     -> a0 : error code
#===============================================================================#
ERROR:
    li    a7, 93            # 'EXIT2' ID
    ecall                   # exits program with whatever error code is in a0

#===============================================================================#
# EXIT: Terminates program with code 0
#===============================================================================#
EXIT:
    li    a7, 10            # 'EXIT' ID
    ecall                   # exits program with code 0
