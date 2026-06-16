#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

int main(void)
{
    int fd;

    char buffer[512];

    fd = open("/dev/sdhealth", O_RDONLY);

    if (fd < 0)
    {
        perror("open");
        return 1;
    }

    int bytes =
        read(fd,
             buffer,
             sizeof(buffer) - 1);

    if (bytes > 0)
    {
        buffer[bytes] = '\0';

        printf("%s\n", buffer);
    }

    close(fd);

    return 0;
}