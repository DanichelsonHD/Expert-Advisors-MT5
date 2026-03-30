#ifndef METH_H
#define METH_H

double GetAbsolute(double value) { if (value < 0) return -(value); else return value;}

double GetPow(double value, int times)
{
    if (value == 0) return 0;
    if (times == 0) return 1;

    double power = 1;
    for (int counter = 0; counter < GetAbsolute(times); counter++) { power *= value; }

    if (times < 0) return 1 / power;

    return power;
}

double GetExtimative(double value, double previousExtimative) 
{
    if (previousExtimative == 0) previousExtimative = 1e-6;

    return previousExtimative + (value - previousExtimative*previousExtimative) / (previousExtimative * 2); 
}

double GetExtimative(double value, double previousExtimative, int times) 
{
    if (previousExtimative == 0) previousExtimative = 1e-6;
    double tempNumber = GetPow(previousExtimative, times);
    return previousExtimative + (value - tempNumber) / (times * tempNumber / previousExtimative);
}


double GetRoot(double value)
{
    if (value == 0) return 0;
    if (value < 0) return -1;

    int aproxPerfectRoot = 1;
    while (value >= aproxPerfectRoot*aproxPerfectRoot) { aproxPerfectRoot++; }
    
    aproxPerfectRoot -= 1;

    if (value == aproxPerfectRoot*aproxPerfectRoot) return (double)aproxPerfectRoot;

    double aproxRoot = GetExtimative(value, aproxPerfectRoot);

    for (int counter = 0; counter < 8; counter++)
    {
        if (GetAbsolute(value - aproxRoot*aproxRoot) < 1e-6) break;
        aproxRoot = GetExtimative(value, aproxRoot);
    }

    return aproxRoot;
}

double GetRoot(double value, int times)
{
    if (value == 0) return 0;
    if (times <= 0) return -1;
    if (times == 1) return value;

    if (value < 0)
    {
        if (times % 2 == 1)
            return -GetRoot(-value, times);
        else
            return -1; 
    }

    int aproxPerfectRoot = 1;
    while (value >= GetPow(aproxPerfectRoot, times)) { aproxPerfectRoot++; }
    
    aproxPerfectRoot -= 1;

    if (value == GetPow(aproxPerfectRoot, times)) return (double)aproxPerfectRoot;

    double aproxRoot = GetExtimative(value, aproxPerfectRoot, times);

    for (int counter = 0; counter < 8; counter++)
    {
        if (GetAbsolute(value - GetPow(aproxRoot, times)) < 1e-6) break;
        aproxRoot = GetExtimative(value, aproxRoot, times);
    }

    return aproxRoot;
}

#endif