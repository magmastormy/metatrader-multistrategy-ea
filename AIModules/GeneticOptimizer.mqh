//+------------------------------------------------------------------+
//| GeneticOptimizer.mqh                                             |
//| Genetic Algorithm for Strategy Parameter Optimization           |
//| Based on neural_networks.md specification                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#ifndef __GENETIC_OPTIMIZER_MQH__
#define __GENETIC_OPTIMIZER_MQH__

#define POPULATION_SIZE 50
#define MUTATION_RATE 0.15

//+------------------------------------------------------------------+
//| Strategy Parameter Set Structure                                 |
//+------------------------------------------------------------------+
struct SStrategyParameters
{
    // Order Block Parameters
    double obMinDisplacement;      // 1.5 - 2.0
    double obStrengthThreshold;    // 0.6 - 0.8
    
    // Liquidity Parameters
    double liquidityTolerance;     // 10 - 15 pips
    bool sweepConfirmation;        // true/false
    
    // Entry Parameters
    int minConfluence;             // 2 - 4
    double minConfidenceThreshold; // 0.55 - 0.70
    
    // Risk Parameters
    double riskPercent;            // 1.0 - 2.0
    double minRR;                  // 1.5 - 3.0
    
    // Session Parameters
    bool londonKillZone;
    bool nyKillZone;
    bool asianKillZone;
    
    // Fitness Results
    double fitness;
    int tradesCount;
    double profitFactor;
    double winRate;
    
    SStrategyParameters()
    {
        obMinDisplacement = 1.5;
        obStrengthThreshold = 0.7;
        liquidityTolerance = 12.0;
        sweepConfirmation = true;
        minConfluence = 3;
        minConfidenceThreshold = 0.60;
        riskPercent = 1.5;
        minRR = 2.0;
        londonKillZone = true;
        nyKillZone = true;
        asianKillZone = false;
        fitness = 0.0;
        tradesCount = 0;
        profitFactor = 0.0;
        winRate = 0.0;
    }
};

//+------------------------------------------------------------------+
//| Backtest Results Structure                                       |
//+------------------------------------------------------------------+
struct SBacktestResults
{
    double sharpeRatio;
    double winRate;
    double maxDrawdown;
    double profitFactor;
    int tradesCount;
    double netProfit;
    
    SBacktestResults()
    {
        sharpeRatio = 0.0;
        winRate = 0.0;
        maxDrawdown = 0.0;
        profitFactor = 0.0;
        tradesCount = 0;
        netProfit = 0.0;
    }
};

//+------------------------------------------------------------------+
//| Genetic Algorithm Optimizer Class                                |
//+------------------------------------------------------------------+
class CGeneticOptimizer
{
private:
    SStrategyParameters m_population[POPULATION_SIZE];
    int m_generation;
    bool m_initialized;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    datetime m_optimizationStart;
    datetime m_optimizationEnd;
    
public:
    CGeneticOptimizer()
    {
        m_generation = 0;
        m_initialized = false;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_optimizationStart = 0;
        m_optimizationEnd = 0;
    }
    
    bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe, datetime optimizationStart, datetime optimizationEnd)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_optimizationStart = optimizationStart;
        m_optimizationEnd = optimizationEnd;
        
        // Initialize random population
        InitializePopulation();
        
        m_initialized = true;
        PrintFormat("[GENETIC-OPT] Initialized | Population: %d | Symbol: %s", POPULATION_SIZE, symbol);
        return true;
    }
    
    void InitializePopulation()
    {
        for(int i = 0; i < POPULATION_SIZE; i++)
        {
            m_population[i].obMinDisplacement = RandomDouble(1.0, 2.5);
            m_population[i].obStrengthThreshold = RandomDouble(0.5, 0.9);
            m_population[i].liquidityTolerance = RandomDouble(5, 20);
            m_population[i].sweepConfirmation = (MathRand() % 2 == 0);
            m_population[i].minConfluence = 2 + (MathRand() % 3);
            m_population[i].minConfidenceThreshold = RandomDouble(0.50, 0.75);
            m_population[i].riskPercent = RandomDouble(0.5, 2.5);
            m_population[i].minRR = RandomDouble(1.2, 3.5);
            m_population[i].londonKillZone = (MathRand() % 2 == 0);
            m_population[i].nyKillZone = (MathRand() % 2 == 0);
            m_population[i].asianKillZone = (MathRand() % 2 == 0);
            m_population[i].fitness = 0.0;
        }
        
        Print("[GENETIC-OPT] Population initialized with random parameters");
    }
    
    void RunGeneration()
    {
        if(!m_initialized)
            return;
        
        PrintFormat("[GENETIC-OPT] Running generation %d", m_generation);
        
        // Step 1: Evaluate fitness for all individuals
        EvaluateFitness();
        
        // Step 2: Sort by fitness
        SortByFitness();
        
        // Step 3: Print best result
        PrintFormat("[GENETIC-OPT] Best fitness: %.4f | WinRate: %.2f%% | PF: %.2f | Trades: %d",
                   m_population[0].fitness,
                   m_population[0].winRate * 100,
                   m_population[0].profitFactor,
                   m_population[0].tradesCount);
        
        // Step 4: Create next generation
        CreateNextGeneration();
        
        m_generation++;
    }
    
    void EvaluateFitness()
    {
        for(int i = 0; i < POPULATION_SIZE; i++)
        {
            // Simulate backtest with these parameters
            SBacktestResults results = SimulateBacktest(m_population[i]);
            
            // Calculate composite fitness score
            double fitness = 0.0;
            
            // Component 1: Sharpe Ratio (40% weight)
            double sharpeScore = MathMin(results.sharpeRatio / 2.0, 1.0);
            fitness += sharpeScore * 0.40;
            
            // Component 2: Win Rate (30% weight)
            fitness += results.winRate * 0.30;
            
            // Component 3: Trade Count (10% weight)
            double tradeCountScore = 0.0;
            if(results.tradesCount >= 20 && results.tradesCount <= 100)
                tradeCountScore = 1.0;
            else if(results.tradesCount < 20)
                tradeCountScore = results.tradesCount / 20.0;
            else
                tradeCountScore = 100.0 / results.tradesCount;
            
            fitness += tradeCountScore * 0.10;
            
            // Component 4: Max Drawdown (20% weight) - lower is better
            double ddScore = 1.0 - (results.maxDrawdown / 30.0);
            ddScore = MathMax(0.0, ddScore);
            fitness += ddScore * 0.20;
            
            // Store results
            m_population[i].fitness = fitness;
            m_population[i].tradesCount = results.tradesCount;
            m_population[i].profitFactor = results.profitFactor;
            m_population[i].winRate = results.winRate;
        }
    }
    
    SBacktestResults SimulateBacktest(SStrategyParameters &params)
    {
        // Simplified backtest simulation
        // In production, this would run actual strategy with these parameters
        SBacktestResults results;
        
        // Generate synthetic results based on parameter quality
        double paramQuality = EvaluateParameterQuality(params);
        
        results.tradesCount = (int)(30 + MathRand() % 50);
        results.winRate = 0.40 + (paramQuality * 0.25);
        results.profitFactor = 1.0 + (paramQuality * 1.5);
        results.sharpeRatio = paramQuality * 2.0;
        results.maxDrawdown = 15.0 - (paramQuality * 10.0);
        results.netProfit = results.tradesCount * paramQuality * 100;
        
        return results;
    }
    
    double EvaluateParameterQuality(SStrategyParameters &params)
    {
        // Score parameters based on known good ranges
        double score = 0.0;
        int components = 0;
        
        // OB displacement (optimal around 1.5-2.0)
        if(params.obMinDisplacement >= 1.3 && params.obMinDisplacement <= 2.2)
            score += 1.0;
        components++;
        
        // OB strength (optimal around 0.65-0.75)
        if(params.obStrengthThreshold >= 0.60 && params.obStrengthThreshold <= 0.80)
            score += 1.0;
        components++;
        
        // Liquidity tolerance (optimal around 10-15)
        if(params.liquidityTolerance >= 8 && params.liquidityTolerance <= 18)
            score += 1.0;
        components++;
        
        // Confluence (optimal 2-3)
        if(params.minConfluence >= 2 && params.minConfluence <= 3)
            score += 1.0;
        components++;
        
        // Confidence threshold (optimal 0.60-0.65)
        if(params.minConfidenceThreshold >= 0.55 && params.minConfidenceThreshold <= 0.70)
            score += 1.0;
        components++;
        
        // Risk percent (optimal 1.0-1.5)
        if(params.riskPercent >= 0.8 && params.riskPercent <= 2.0)
            score += 1.0;
        components++;
        
        // Min RR (optimal 2.0-2.5)
        if(params.minRR >= 1.8 && params.minRR <= 3.0)
            score += 1.0;
        components++;
        
        // Kill zones (at least 2 enabled is good)
        int kzCount = 0;
        if(params.londonKillZone) kzCount++;
        if(params.nyKillZone) kzCount++;
        if(params.asianKillZone) kzCount++;
        if(kzCount >= 2)
            score += 1.0;
        components++;
        
        return score / components;
    }
    
    void SortByFitness()
    {
        // Bubble sort (sufficient for small population)
        for(int i = 0; i < POPULATION_SIZE - 1; i++)
        {
            for(int j = 0; j < POPULATION_SIZE - i - 1; j++)
            {
                if(m_population[j].fitness < m_population[j + 1].fitness)
                {
                    SStrategyParameters temp = m_population[j];
                    m_population[j] = m_population[j + 1];
                    m_population[j + 1] = temp;
                }
            }
        }
    }
    
    void CreateNextGeneration()
    {
        int eliteCount = (int)(POPULATION_SIZE * 0.20);
        SStrategyParameters newPopulation[POPULATION_SIZE];
        
        // Keep elite (top 20%)
        for(int i = 0; i < eliteCount; i++)
        {
            newPopulation[i] = m_population[i];
        }
        
        // Create rest through crossover and mutation
        for(int i = eliteCount; i < POPULATION_SIZE; i++)
        {
            // Select two parents from top 50%
            int parent1Idx = MathRand() % (POPULATION_SIZE / 2);
            int parent2Idx = MathRand() % (POPULATION_SIZE / 2);
            
            // Crossover
            newPopulation[i] = Crossover(m_population[parent1Idx], m_population[parent2Idx]);
            
            // Mutation
            if(RandomDouble(0, 1) < MUTATION_RATE)
            {
                Mutate(newPopulation[i]);
            }
        }
        
        // Replace population
        for(int i = 0; i < POPULATION_SIZE; i++)
        {
            m_population[i] = newPopulation[i];
        }
    }
    
    SStrategyParameters Crossover(SStrategyParameters &parent1, SStrategyParameters &parent2)
    {
        SStrategyParameters child;
        
        // Uniform crossover (50% from each parent)
        child.obMinDisplacement = (MathRand() % 2 == 0) ? parent1.obMinDisplacement : parent2.obMinDisplacement;
        child.obStrengthThreshold = (MathRand() % 2 == 0) ? parent1.obStrengthThreshold : parent2.obStrengthThreshold;
        child.liquidityTolerance = (MathRand() % 2 == 0) ? parent1.liquidityTolerance : parent2.liquidityTolerance;
        child.sweepConfirmation = (MathRand() % 2 == 0) ? parent1.sweepConfirmation : parent2.sweepConfirmation;
        child.minConfluence = (MathRand() % 2 == 0) ? parent1.minConfluence : parent2.minConfluence;
        child.minConfidenceThreshold = (MathRand() % 2 == 0) ? parent1.minConfidenceThreshold : parent2.minConfidenceThreshold;
        child.riskPercent = (MathRand() % 2 == 0) ? parent1.riskPercent : parent2.riskPercent;
        child.minRR = (MathRand() % 2 == 0) ? parent1.minRR : parent2.minRR;
        child.londonKillZone = (MathRand() % 2 == 0) ? parent1.londonKillZone : parent2.londonKillZone;
        child.nyKillZone = (MathRand() % 2 == 0) ? parent1.nyKillZone : parent2.nyKillZone;
        child.asianKillZone = (MathRand() % 2 == 0) ? parent1.asianKillZone : parent2.asianKillZone;
        
        return child;
    }
    
    void Mutate(SStrategyParameters &params)
    {
        // Random mutation of one parameter
        int mutateParam = MathRand() % 11;
        
        switch(mutateParam)
        {
            case 0:
                params.obMinDisplacement += RandomDouble(-0.3, 0.3);
                params.obMinDisplacement = MathMax(1.0, MathMin(2.5, params.obMinDisplacement));
                break;
            case 1:
                params.obStrengthThreshold += RandomDouble(-0.1, 0.1);
                params.obStrengthThreshold = MathMax(0.5, MathMin(0.9, params.obStrengthThreshold));
                break;
            case 2:
                params.liquidityTolerance += RandomDouble(-5, 5);
                params.liquidityTolerance = MathMax(5, MathMin(20, params.liquidityTolerance));
                break;
            case 3:
                params.sweepConfirmation = !params.sweepConfirmation;
                break;
            case 4:
                params.minConfluence += (MathRand() % 3) - 1;
                params.minConfluence = (int)MathMax(1, MathMin(5, params.minConfluence));
                break;
            case 5:
                params.minConfidenceThreshold += RandomDouble(-0.05, 0.05);
                params.minConfidenceThreshold = MathMax(0.45, MathMin(0.80, params.minConfidenceThreshold));
                break;
            case 6:
                params.riskPercent += RandomDouble(-0.3, 0.3);
                params.riskPercent = MathMax(0.5, MathMin(3.0, params.riskPercent));
                break;
            case 7:
                params.minRR += RandomDouble(-0.3, 0.3);
                params.minRR = MathMax(1.0, MathMin(4.0, params.minRR));
                break;
            case 8:
                params.londonKillZone = !params.londonKillZone;
                break;
            case 9:
                params.nyKillZone = !params.nyKillZone;
                break;
            case 10:
                params.asianKillZone = !params.asianKillZone;
                break;
        }
    }
    
    SStrategyParameters GetBestParameters()
    {
        // Return top individual
        return m_population[0];
    }
    
    void OptimizeGenerations(int generations)
    {
        for(int i = 0; i < generations; i++)
        {
            RunGeneration();
        }
        
        PrintFormat("[GENETIC-OPT] Optimization complete after %d generations", generations);
        PrintFormat("[GENETIC-OPT] Best parameters - Fitness: %.4f", m_population[0].fitness);
    }
    
    double RandomDouble(double min, double max)
    {
        return min + (max - min) * (MathRand() / 32768.0);
    }
};

#endif
