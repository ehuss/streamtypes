#include <stdlib.h>
#include <stdio.h>
#include <libgen.h>
#include "png.h"

#define INBUFSIZE 4096

static png_structp png_ptr;
static png_infop info_ptr;
static int done = 0;
static double LUT_exponent = 1.0;  // 1.8/2.61 for mac.
static double CRT_exponent = 2.2;
static double display_exponent = 2.2; // LUT_exponent * CRT_exponent
static png_uint_32 width, height;
static int rowbytes;
static int channels;
static unsigned char *image_data;
static unsigned char **row_pointers;
static FILE *outfile;

static void pngdata_info_callback(png_structp png_ptr, png_infop info_ptr)
{
    int bit_depth, color_type, passes;
    double gamma;

    png_get_IHDR(png_ptr, info_ptr, &width, &height, &bit_depth, &color_type, NULL, NULL, NULL);
    if (color_type == PNG_COLOR_TYPE_PALETTE) {
        png_set_palette_to_rgb(png_ptr);
    }
    // if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8) {
    //     png_set_expand_gray_1_2_4_to_8(png_ptr);
    // }
    if (png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS)) {
        png_set_tRNS_to_alpha(png_ptr);
    }
    if (png_get_gAMA(png_ptr, info_ptr, &gamma)) {
        png_set_gamma(png_ptr, display_exponent, gamma);
    } else {
        png_set_gamma(png_ptr, display_exponent, 0.45455);
    }
    passes = png_set_interlace_handling(png_ptr);
    png_read_update_info(png_ptr, info_ptr);
    // Because transforms may have changed bit_depth.
    bit_depth = png_get_bit_depth(png_ptr, info_ptr);
    // In case of palette.
    color_type = png_get_color_type(png_ptr, info_ptr);
    fwrite(&width, sizeof(width), 1, outfile);
    fwrite(&height, sizeof(height), 1, outfile);
    fwrite(&bit_depth, sizeof(bit_depth), 1, outfile);
    fwrite(&color_type, sizeof(color_type), 1, outfile);

    rowbytes = (int)png_get_rowbytes(png_ptr, info_ptr);
    channels = png_get_channels(png_ptr, info_ptr);
    fwrite(&rowbytes, sizeof(rowbytes), 1, outfile);
    fwrite(&channels, sizeof(channels), 1, outfile);

    image_data = (unsigned char *)malloc(rowbytes * height);
    if (!image_data) return;
    row_pointers = (unsigned char **)malloc(height * sizeof(unsigned char *));
    if (!row_pointers) return;
    for (png_uint_32 i=0; i < height; i++) {
        row_pointers[i] = image_data + i*rowbytes;
    }

    return;
}

static int lastPass = 0;
static int passHasData = 0;

static void
savePass()
{
    if (passHasData) {
        for (int i=0; i<height; i++) {
            unsigned char * row = row_pointers[i];
            fwrite(row, 1, rowbytes, outfile);
        }
    }
    passHasData = 0;
}

static void pngdata_row_callback(png_structp png_ptr, png_bytep new_row,
                                 png_uint_32 row_num, int pass)
{
    unsigned char *row;

    if (pass != lastPass) {
        savePass();
        lastPass = pass;
    }

    if (new_row) {
        passHasData = 1;
        png_progressive_combine_row(png_ptr, row_pointers[row_num], new_row);
    }

    // Display row_num.
    // printf("Pass %i Row %i: ", pass, row_num);
    // for (int i=0; i<rowbytes; i++) {
    //     printf("%i ", row[i]);
    // }
    // printf("\n");
}

static void pngdata_end_callback()
{
    savePass();
    done = 1;
}

static int pngdata_init()
{
    png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png_ptr) return -1;
    info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr) return -1;

    if (setjmp(png_jmpbuf(png_ptr))) {
        png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
        return -1;
    }

    png_set_progressive_read_fn(png_ptr, NULL,
        pngdata_info_callback, pngdata_row_callback, pngdata_end_callback);
    return 0;
}

static int pngdata_decode_data(unsigned char *inbuf, int length)
{
    if (setjmp(png_jmpbuf(png_ptr))) {
        return -1;
    }
    png_process_data(png_ptr, info_ptr, inbuf, length);
    return 0;
}

static void pngdata_cleanup()
{
    png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
    free(image_data);
    free(row_pointers);
}

// // Skip corrupt files.
// static char *skip_files[] = {
//     "xc1n0g08.png",
//     "xc9n2c08.png",
//     "xcrn0g04.png",
//     "xcsn0g01.png",
//     "xd0n2c08.png",
//     "xd3n2c08.png",
//     "xd9n2c08.png",
//     "xdtn0g01.png",
//     "xhdn0g08.png",
//     "xlfn0g04.png",
//     "xs1n0g01.png",
//     "xs2n0g01.png",
//     "xs4n0g01.png",
//     "xs7n0g01.png",
//     NULL
// };

int main(int argc, char const *argv[])
{
    FILE *infile;
    const char *filename;
    char out_filename[1024];
    int rc;
    int incount;
    unsigned char inbuf[INBUFSIZE];
    // int found;

    for (int argi = 1; argi < argc; argi++) {
        filename = argv[argi];
        // found = 0;
        // for (int skipi=0; skip_files[skipi]; skipi++) {
        //     if (strcmp(basename(filename), skip_files[skipi]) == 0) {
        //         printf("Skipping %s\n", filename);
        //         found = 1;
        //         break;
        //     }
        // }
        // if (found) continue;
        printf("Starting %s\n", filename);
        sprintf(out_filename, "%s.data", filename);
        infile = fopen(filename, "r");
        if (infile == NULL) {
            fprintf(stderr, "Failed to open file %s\n", filename);
            return 1;
        }

        incount = fread(inbuf, 1, INBUFSIZE, infile);
        if (incount < 8 || !png_check_sig(inbuf, 8)) {
            fprintf(stderr, "%s is not a png file.\n", filename);
            return 1;
        }

        outfile = fopen(out_filename, "w");
        if (outfile == NULL) {
            fprintf(stderr, "Failed to open output file %s", out_filename);
            return 1;
        }

        rc = pngdata_init();
        if (rc) return 1;

        while (1) {
            if (pngdata_decode_data(inbuf, incount)) return 1;
            if (incount != INBUFSIZE) {
                // EOF.
                if (done) {
                    break;
                } else {
                    fprintf(stderr, "Truncated file.\n");
                    return 1;
                }
            }
            incount = fread(inbuf, 1, INBUFSIZE, infile);
        }

        fclose(infile);
        fclose(outfile);
        pngdata_cleanup();
        printf("Finished %s\n", filename);

    }

    return 0;
}
