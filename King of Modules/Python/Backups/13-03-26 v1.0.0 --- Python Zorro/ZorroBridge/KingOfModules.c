#include <default.c>

function run()
{
    set(PYTHON);

    asset("EURUSD");
    BarPeriod = 60;
    LookBack = 200;

    int signal = python("EA_KingofModules.signal");

    if(signal == 1)
        enterLong();

    if(signal == -1)
        enterShort();
}
