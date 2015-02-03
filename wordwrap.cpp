#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
        if(argc>4) {
                fprintf(stderr,"usage: wordwrap margin [infile [outfile]]\n");
                return 1;
        }
        
        int margin;
        if(argc>1)
                margin = atoi(argv[1]);
        else
                margin = 80;
        
        FILE *ifp,*ofp;
        
        if(argc>2) {
                ifp=fopen(argv[2],"r");
                if(!ifp) {
                        perror(argv[2]);
                        return 2;
                }
        } else
                ifp = stdin;

        if(argc>3) {
                ofp=fopen(argv[3],"w");
                if(!ofp) {
                        perror(argv[3]);
                        return 3;
                }
        } else
                ofp = stdout;
                
        static char buf[8192];
        while(fgets(buf,8192,ifp)) {
                char *sp=buf;
                while(*sp) {
                        char *ep=sp;
                        while(*ep && (ep-sp)<margin)
                                ep++;
                        while(ep>sp && *ep!=' ' && *ep!='\n')
                                ep--;
                        if(ep!=sp) {
                                fwrite(sp,1,ep-sp,ofp);
                        } else {
                                //loooong word
                                while(*ep && *ep!=' ' && *ep!='\n')
                                        ep++;
                                fwrite(sp,1,ep-sp,ofp);
                        }
                        putc('\n',ofp);
                        sp=ep;
                        while(*sp==' ' || *sp=='\n') sp++;
                }
        }
        fclose(ifp);
        fclose(ofp);
        
        return 0;

}

