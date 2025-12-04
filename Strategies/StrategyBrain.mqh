#ifndef _STRATEGY_BRAIN_MQH_
#define _STRATEGY_BRAIN_MQH_

//+------------------------------------------------------------------+
//| Neural Network Implementation for Strategy Brain                 |
//| Uses a simple feedforward network with backpropagation          |
//+------------------------------------------------------------------+

#include <Arrays\ArrayObj.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Math\Stat\Math.mqh>
#include <Files\FileTxt.mqh>
#include "../Utilities/Utilities.mqh"

//+------------------------------------------------------------------+
//| Neural Network Layer                                            |
//+------------------------------------------------------------------+
class CNeuralLayer {
private:
    int m_inputs;
    int m_neurons;
    CArrayDouble m_weights;
    CArrayDouble m_biases;
    CArrayDouble m_outputs;
    double m_learningRate;

public:
    CNeuralLayer(int inputs, int neurons, double learningRate = 0.1) {
        m_inputs = inputs;
        m_neurons = neurons;
        m_learningRate = learningRate;
        
        // Initialize weights and biases with small random values
        m_weights.Resize(m_inputs * m_neurons);
        m_biases.Resize(m_neurons);
        m_outputs.Resize(m_neurons);
        
        for(int i = 0; i < m_weights.Total(); i++) {
            m_weights.Update(i, (MathRand() / 32767.0 - 0.5) * 0.1);
        }
        
        for(int i = 0; i < m_biases.Total(); i++) {
            m_biases.Update(i, (MathRand() / 32767.0 - 0.5) * 0.1);
        }
    }
    
    // Forward pass
    bool Forward(const CArrayDouble &inputs, CArrayDouble &outputs) {
        if(inputs.Total() != m_inputs) return false;
        
        for(int i = 0; i < m_neurons; i++) {
            double sum = 0.0;
            for(int j = 0; j < m_inputs; j++) {
                sum += inputs.At(j) * m_weights.At(i * m_inputs + j);
            }
            sum += m_biases.At(i);
            m_outputs.Update(i, MathTanh(sum));  // Using tanh activation
        }
        
        outputs = m_outputs;
        return true;
    }
    
    // Backward pass
    bool Backward(const CArrayDouble &inputs, const CArrayDouble &gradient, CArrayDouble &inputGradient) {
        if(gradient.Total() != m_neurons) return false;
        
        inputGradient.Resize(m_inputs);
        
        // Calculate gradients for weights and biases
        for(int i = 0; i < m_neurons; i++) {
            double grad = gradient[i] * (1.0 - m_outputs[i] * m_outputs[i]);  // Derivative of tanh
            
            // Update weights
            for(int j = 0; j < m_inputs; j++) {
                double weightGrad = grad * inputs.At(j);
                int idx = i * m_inputs + j;
                double newWeight = m_weights.At(idx) - m_learningRate * weightGrad;
                m_weights.Update(idx, newWeight);
                inputGradient.Update(j, inputGradient.At(j) + m_weights.At(idx) * grad);
            }
            
            // Update bias
            m_biases.Update(i, m_biases.At(i) - m_learningRate * grad);
        }
        
        return true;
    }
    
    // Save/Load methods
    bool Save(int file_handle) {
        if(file_handle == INVALID_HANDLE) return false;
        
        // Save weights
        int totalWeights = m_weights.Total();
        if(FileWriteInteger(file_handle, totalWeights, INT_VALUE) <= 0) return false;
        
        for(int i = 0; i < totalWeights; i++) {
            double val = m_weights.At(i);
            if(FileWriteDouble(file_handle, val) <= 0) {
                FileClose(file_handle);
                return false;
            }
        }
        
        // Save biases
        int totalBiases = m_biases.Total();
        if(FileWriteInteger(file_handle, totalBiases, INT_VALUE) <= 0) {
            FileClose(file_handle);
            return false;
        }
        
        for(int i = 0; i < totalBiases; i++) {
            double val = m_biases.At(i);
            if(FileWriteDouble(file_handle, val) <= 0) {
                FileClose(file_handle);
                return false;
            }
        }
        
        return true;
    }
    
    bool Load(int file_handle) {
        if(file_handle == INVALID_HANDLE) return false;
        
        // Load weights
        int totalWeights = (int)FileReadInteger(file_handle, INT_VALUE);
        if(totalWeights != m_weights.Total()) {
            Print("Mismatch in weights count. Expected: ", m_weights.Total(), ", Found: ", totalWeights);
            return false;
        }
        
        for(int i = 0; i < totalWeights; i++) {
            if(FileIsEnding(file_handle)) return false;
            double val = FileReadDouble(file_handle);
            m_weights.Update(i, val);
        }
        
        // Load biases
        int totalBiases = (int)FileReadInteger(file_handle, INT_VALUE);
        if(totalBiases != m_biases.Total()) {
            Print("Mismatch in biases count. Expected: ", m_biases.Total(), ", Found: ", totalBiases);
            return false;
        }
        
        for(int i = 0; i < totalBiases; i++) {
            if(FileIsEnding(file_handle)) return false;
            double val = FileReadDouble(file_handle);
            m_biases.Update(i, val);
        }
        
        return true;
    }
    
    // Accessor methods
    int Inputs() const { return m_inputs; }
    int Neurons() const { return m_neurons; }
};

//+------------------------------------------------------------------+
//| Neural Network                                                 |
//+------------------------------------------------------------------+
class CNeuralNetwork {
private:
    CNeuralLayer *m_layers[];
    bool m_initialized;
    
public:
    CNeuralNetwork() : m_initialized(false) {
        ArrayResize(m_layers, 0);
    }
    
    ~CNeuralNetwork() {
        for(int i = 0; i < ArraySize(m_layers); i++) {
            delete m_layers[i];
        }
        ArrayResize(m_layers, 0);
    }
    
    void Deinitialize() {
        for(int i = 0; i < ArraySize(m_layers); i++) {
            delete m_layers[i];
        }
        ArrayResize(m_layers, 0);
        m_initialized = false;
    }
    
    // Create network with architecture
    bool Create(const int &architecture[], double learningRate = 0.1) {
        Deinitialize();
        if(ArraySize(architecture) < 2) {
            Print("Error: Network must have at least 2 layers (input and output)");
            return false;
        }
        ArrayResize(m_layers, ArraySize(architecture) - 1);
        for(int i = 1; i < ArraySize(architecture); i++) {
            m_layers[i-1] = new CNeuralLayer(architecture[i-1], architecture[i], learningRate);
            if(!POINTER_VALID(m_layers[i-1])) {
                Print("Failed to create layer ", i);
                Deinitialize();
                return false;
            }
        }
        m_initialized = true;
        return true;
    }
    
    // Forward pass through the network
    bool Predict(const double &inputs[], double &outputs[]) {
        if(!m_initialized || ArraySize(m_layers) == 0) return false;
        CArrayDouble currentInputs;
        currentInputs.Resize(ArraySize(inputs));
        for(int i = 0; i < ArraySize(inputs); i++)
            currentInputs.Update(i, inputs[i]);
        CArrayDouble currentOutputs;
        // Forward pass through all layers
        for(int i = 0; i < ArraySize(m_layers); i++) {
            CNeuralLayer *layer = m_layers[i];
            if(!POINTER_VALID(layer)) return false;
            currentOutputs.Resize(layer.Neurons());
            if(!layer.Forward(currentInputs, currentOutputs)) return false;
            currentInputs.Resize(currentOutputs.Total());
            for(int j = 0; j < currentOutputs.Total(); j++)
                currentInputs.Update(j, currentOutputs.At(j));
        }
        ArrayResize(outputs, currentOutputs.Total());
        for(int i = 0; i < currentOutputs.Total(); i++)
            outputs[i] = currentOutputs.At(i);
        return true;
    }
    
    // Train on a single sample
    bool TrainSample(const double &inputs[], const double &targets[]) {
        if(!m_initialized || ArraySize(m_layers) == 0) return false;
        // Forward pass
        int numLayers = ArraySize(m_layers);
        CArrayDouble layerInputs[];
        ArrayResize(layerInputs, numLayers + 1);
        int inputSize = ArraySize(inputs);
        layerInputs[0].Resize(inputSize);
        for(int i = 0; i < inputSize; i++)
            layerInputs[0].Update(i, inputs[i]);
        for(int i = 0; i < numLayers; i++) {
            CNeuralLayer *layer = m_layers[i];
            if(!POINTER_VALID(layer)) return false;
            int n = layer.Neurons();
            layerInputs[i+1].Resize(n);
            if(!layer.Forward(layerInputs[i], layerInputs[i+1])) return false;
        }
        // Backward pass
        int targetSize = ArraySize(targets);
        CArrayDouble gradient;
        gradient.Resize(targetSize);
        for(int i = 0; i < targetSize; i++)
            gradient.Update(i, 2.0 * (layerInputs[numLayers].At(i) - targets[i]));
        for(int i = numLayers - 1; i >= 0; i--) {
            CNeuralLayer *layer = m_layers[i];
            if(!POINTER_VALID(layer)) return false;
            CArrayDouble inputGradient;
            int inputSize = layerInputs[i].Total();
            inputGradient.Resize(inputSize);
            if(!layer.Backward(layerInputs[i], gradient, inputGradient)) return false;
            gradient.Resize(inputGradient.Total());
            for(int j = 0; j < inputGradient.Total(); j++)
                gradient.Update(j, inputGradient.At(j));
        }
        return true;
    }
    
    // Save network to file
    bool SaveNetwork(string filename) {
        // Validate filename
        if(StringLen(filename) == 0) {
            Print("Error: Empty filename provided for saving network");
            return false;
        }
        
        // Open file with proper error handling
        int file_handle = FileOpen(filename, FILE_WRITE | FILE_BIN);
        if(file_handle == INVALID_HANDLE) {
            Print("Failed to open file for writing: ", filename, ", error: ", GetLastError());
            return false;
        }
        
        bool success = false;
        
        // Use a try-finally pattern to ensure file is always closed
        do {
            // Save architecture
            int numLayers = ArraySize(m_layers);
            if(numLayers <= 0) {
                Print("Error: No layers to save");
                break;
            }
            
            // Write number of layers + 1 for input layer
            if(FileWriteInteger(file_handle, numLayers + 1, INT_VALUE) != sizeof(int)) {
                Print("Failed to write number of layers, error: ", GetLastError());
                break;
            }
            
            // First layer inputs
            CNeuralLayer *firstLayer = m_layers[0];
            if(!POINTER_VALID(firstLayer)) {
                Print("Error: Invalid first layer pointer");
                break;
            }
            
            int inputs = firstLayer.Inputs();
            if(FileWriteInteger(file_handle, inputs, INT_VALUE) != sizeof(int)) {
                Print("Failed to write number of inputs, error: ", GetLastError());
                break;
            }
            
            // Each layer's neurons
            for(int i = 0; i < numLayers; i++) {
                CNeuralLayer *layer = m_layers[i];
                if(!POINTER_VALID(layer)) {
                    Print("Error: Invalid layer pointer at index ", i);
                    break;
                }
                
                int neurons = layer.Neurons();
                if(FileWriteInteger(file_handle, neurons, INT_VALUE) != sizeof(int)) {
                    Print("Failed to write number of neurons for layer ", i, ", error: ", GetLastError());
                    break;
                }
                
                // If this is the last iteration and we got here, everything is good
                if(i == numLayers - 1) {
                    success = true;
                }
            }
            
            if(!success) break;
            
            // Save weights and biases for each layer
            for(int i = 0; i < numLayers; i++) {
                CNeuralLayer *layer = m_layers[i];
                if(!POINTER_VALID(layer) || !layer.Save(file_handle)) {
                    Print("Failed to save layer ", i);
                    success = false;
                    break;
                }
            }
            
        } while(false); // Only run once, used for flow control with break
        
        // Always close the file handle
        FileClose(file_handle);
        
        if(success) {
            Print("Successfully saved network to ", filename);
        } else {
            Print("Failed to save network to ", filename);
            // Optionally delete the incomplete/corrupt file
            FileDelete(filename);
        }
        
        return success;
    }
    
    // Load network from file
    bool LoadNetwork(string filename) {
        // Validate filename
        if(StringLen(filename) == 0) {
            Print("Error: Empty filename provided for loading network");
            return false;
        }
        
        // Open file with proper error handling
        int file_handle = FileOpen(filename, FILE_READ | FILE_BIN);
        if(file_handle == INVALID_HANDLE) {
            Print("Failed to open file for reading: ", filename, ", error: ", GetLastError());
            return false;
        }
        
        bool success = false;
        int architecture[];
        
        // Use a try-finally pattern to ensure file is always closed
        do {
            // Read number of layers (including input layer)
            int numLayers = (int)FileReadInteger(file_handle, INT_VALUE);
            if(FileIsEnding(file_handle) || numLayers < 2) {
                Print("Invalid number of layers in file: ", numLayers);
                break;
            }
            
            // Resize architecture array
            if(ArrayResize(architecture, numLayers) != numLayers) {
                Print("Failed to allocate memory for architecture array");
                break;
            }
            
            // Read input layer size
            architecture[0] = (int)FileReadInteger(file_handle, INT_VALUE);
            if(FileIsEnding(file_handle) || architecture[0] <= 0) {
                Print("Invalid input layer size: ", architecture[0]);
                break;
            }
            
            // Read hidden and output layer sizes
            for(int i = 1; i < numLayers; i++) {
                architecture[i] = (int)FileReadInteger(file_handle, INT_VALUE);
                if(FileIsEnding(file_handle) || architecture[i] <= 0) {
                    Print("Invalid layer size at index ", i, ": ", architecture[i]);
                    break;
                }
            }
            
            // Create network with this architecture
            if(!Create(architecture)) {
                Print("Failed to create network with the specified architecture");
                break;
            }
            
            // Load weights and biases for each layer
            for(int i = 0; i < ArraySize(m_layers); i++) {
                CNeuralLayer *layer = m_layers[i];
                if(!POINTER_VALID(layer) || !layer.Load(file_handle)) {
                    Print("Failed to load layer ", i);
                    break;
                }
                
                // If this is the last iteration and we got here, everything is good
                if(i == ArraySize(m_layers) - 1) {
                    success = true;
                }
            }
            
        } while(false); // Only run once, used for flow control with break
        
        // Always close the file handle
        FileClose(file_handle);
        
        if(success) {
            Print("Successfully loaded network from ", filename);
        } else {
            Print("Failed to load network from ", filename);
            // Clean up partially loaded network
            Deinitialize();
        }
        
        return success;
    }
    
    // Get number of inputs for the first layer
    int Inputs() const {
        if(ArraySize(m_layers) == 0) return 0;
        CNeuralLayer* layer = m_layers[0];
        if(!POINTER_VALID(layer)) return 0;
        return layer.Inputs();
    }
    
    // Get number of outputs from the last layer
    int Outputs() const {
        if(ArraySize(m_layers) == 0) return 0;
        CNeuralLayer* layer = m_layers[ArraySize(m_layers)-1];
        if(!POINTER_VALID(layer)) return 0;
        return layer.Neurons();
    }
};

// Global neural network instance
CNeuralNetwork g_brainNet;
bool g_brainInitialized = false;

//+------------------------------------------------------------------+
//| Initialize the neural network                                    |
//+------------------------------------------------------------------+
bool BrainInit() {
    if(g_brainInitialized) return true;
    
    // Define network architecture: 10 inputs, 16 hidden neurons, 1 output
    int architecture[] = {10, 16, 1};
    
    // Create the network
    g_brainNet.Create(architecture, 0.01);  // Learning rate = 0.01
    
    // Try to load existing network
    if(g_brainNet.LoadNetwork("brain.nn")) {
        Print("[Brain] Network loaded from file");
    } else {
        Print("[Brain] Created new network with random weights");
    }
    
    g_brainInitialized = true;
    return true;
}

//+------------------------------------------------------------------+
//| Train the network on a single sample                            |
//+------------------------------------------------------------------+
bool BrainTrainSample(const double &inputs[], double target) {
    if(!g_brainInitialized && !BrainInit()) return false;
    
    // Prepare target array
    double targets[1] = {target};
    
    // Train the network
    return g_brainNet.TrainSample(inputs, targets);
}

//+------------------------------------------------------------------+
//| Save the trained network to a file                              |
//+------------------------------------------------------------------+
bool BrainSaveNetwork(string filename = "brain.nn") {
    if(!g_brainInitialized) return false;
    return g_brainNet.SaveNetwork(filename);
}

//+------------------------------------------------------------------+
//| StrategyBrain - Main prediction function                        |
//+------------------------------------------------------------------+

inline ENUM_TRADE_SIGNAL StrategyBrain(double &confidence, const double &inputs[]) {
    if(!g_brainInitialized && !BrainInit()) {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    double outputs[];
    if(!g_brainNet.Predict(inputs, outputs) || ArraySize(outputs) < 1) {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    confidence = outputs[0];
    
    // Return signal based on confidence
    if(confidence > 0.5) return TRADE_SIGNAL_BUY;      // Buy signal
    if(confidence < -0.5) return TRADE_SIGNAL_SELL;     // Sell signal
    return TRADE_SIGNAL_NONE;                           // No signal
}

// Include strategy function declarations
#include "../Core/StrategyFunctions.mqh"

#endif //_STRATEGY_BRAIN_MQH_
