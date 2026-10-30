// Linux-only shim so `import llama` resolves to a libllama found via -Xcc -I / -L.
#include <llama.h>
