# Protest Simulation — Multi-Agent System with BDI and Reinforcement Learning

A agent-based model simulating protest dynamics using the GAMA platform. This simulation explores emergent crowd behavior through heterogeneous agents employing different AI architectures: **BDI (Belief-Desire-Intention)** for police decision-making and **Q-Learning** for journalist behavior optimization.

## Overview

This simulation models a protest scenario with two rival protester groups, police forces, journalists, medics, and bystanders. Each agent type has distinct behaviors, goals, and decision-making mechanisms that interact to produce complex emergent dynamics.

### Key Features

- **BDI Architecture** for police agents with beliefs, desires, and intentions
- **Q-Learning Reinforcement Learning** for journalist positioning optimization
- **FIPA-compliant communication** between agents for coordination and information sharing
- **Dynamic global aggression** influenced by events and agent interactions
- **Real-time visualization** with multiple chart displays tracking simulation metrics

## Agent Types

### 🔴 Protesters (Group A & B)

Two rival protest groups with individual aggression and courage attributes. Protesters can:
- Attack rival group members
- Attack police (if courage is high enough)
- Attack journalists
- Get arrested and detained
- Be healed by medics

**Behavior**: Aggression-driven decision making influenced by both individual traits and global tension levels.

### 🔵 Police (BDI Architecture)

Police agents use a **simple_bdi** control architecture with:

| Component | Description |
|-----------|-------------|
| **Beliefs** | `violence_seen` — awareness of nearby violent acts<br>`need_rest` — recognition of high stress |
| **Desires** | `patrol` — default patrolling behavior<br>`pursue_criminal` — chase violent protesters<br>`rest_at_base` — recover from stress |
| **Plans** | `do_patrol` — wander around protest area<br>`do_pursue` — chase and arrest violent actors<br>`do_rest` — return to police HQ to recover |

Police also coordinate via FIPA messaging to request backup during pursuits.

### 📰 Journalists (Q-Learning)

Journalists implement a **Q-Learning algorithm** to optimize their documentation strategy:

**State Space**:
- Distance to nearest event: `vclose`, `close`, `med`, `far`
- Danger level: `safe`, `mod`, `danger`  
- Event type: `none`, `attack`, `arrest`

**Action Space**:
- `closer` — move toward the event
- `away` — move away from the event
- `document` — attempt to document the event
- `flee` — emergency escape

**Reward Structure**:
| Outcome | Reward |
|---------|--------|
| Document from very close | +40 |
| Document from close | +25 |
| Document from medium distance | +12 |
| Document from far | +5 |
| Get hit by protester | -50 |

The Q-Learning update follows: `Q(s,a) ← Q(s,a) + α[R + γ·max(Q(s',a')) - Q(s,a)]`

### 🟢 Medics

Medics search for and heal injured protesters. They:
- Locate the most critically injured protester
- Travel to and heal them
- Return to the ambulance base when exhausted

### 🔷 Bystanders

Passive observers that:
- Watch ongoing events
- Accumulate boredom or fear based on activity
- Leave the simulation when bored or too frightened

## Global Dynamics

### Aggression Model

Global aggression (`0.25` to `0.9`) is influenced by:

| Event | Effect |
|-------|--------|
| Attack occurs | +0.01 |
| Arrest made | +0.02 |
| Random tension spike (40% chance every 30 cycles) | +0.05 to +0.15 |
| Major incident (30% chance every 200 cycles) | +0.20 |
| Police presence | -0.003 per officer (every 20 cycles) |
| Detained protesters | -0.005 per detainee (every 20 cycles) |
| Natural decay | -base_decay × (1 + aggression × 3) per cycle |

## Installation

### Requirements

- **GAMA Platform** 1.9.x or later
- Download from: [https://gama-platform.org/download](https://gama-platform.org/download)

### Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/protest-simulation.git
   ```

2. Open GAMA Platform

3. Import the project:
   - File → Import → GAMA Project
   - Select the cloned repository folder

4. Open `ProtestSimulation.gaml`

5. Run the `ProtestSimulation` experiment

## Configuration Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `nb_protesters_A` | 15 | 5-30 | Number of Group A protesters |
| `nb_protesters_B` | 15 | 5-30 | Number of Group B protesters |
| `nb_police` | 10 | 5-20 | Number of police officers |
| `nb_journalists` | 3 | 1-10 | Number of journalists |
| `global_aggression` | 0.5 | 0.2-0.8 | Initial aggression level |
| `aggression_attack_threshold` | 0.5 | 0.3-0.7 | Threshold for attack initiation |

### Q-Learning Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `learning_rate` | 0.2 | Weight given to new experiences |
| `discount_factor` | 0.95 | Value of future rewards |
| `exploration_rate` | 0.3 | Initial random exploration probability |
| `exploration_decay` | 0.995 | Rate of exploration reduction per cycle |
| `min_exploration_rate` | 0.05 | Minimum exploration maintained |

## Visualization Displays

### Main Simulation View
2D representation of all agents with color-coded states:
- Police perception radius visualization
- Stress bar indicators
- Agent state colors (attacking, detained, documenting, etc.)

### Dynamics Charts
- **Aggression**: Global tension over time
- **Event Rates**: Smoothed attack, arrest, and documentation rates

### Journalist Performance (Q-Learning)
- **Cumulative Rewards**: Learning progress per journalist
- **Documentation vs Hits**: Success/failure tracking

### Police Performance (BDI)
- **Stress Levels**: Individual officer stress over time
- **Total Arrests**: Cumulative arrest count

### Status Overview
- Pie charts showing agent distributions
- Exploration rate (ε) decay over time

## Technical Implementation

### Communication Protocol

Agents communicate using **FIPA (Foundation for Intelligent Physical Agents)** protocol:

```
Police → Police: backup_needed (request assistance)
Police → Protester: (arrest actions)
Protester → Police: hit (attack notification)
Protester → Journalist: hit (attack notification)
IncidentCoordinator → Protesters: aggression_boost (major incident)
Journalist → All: status_query (event detection)
```

### Species Hierarchy

```
Protester (base species)
├── ProtesterA
└── ProtesterB

Police (simple_bdi control)
Journalist (Q-Learning)
Medic
Bystander
IncidentCoordinator
```

### Location Markers

- **Police HQ** (blue square): Police rest/respawn point, detention area
- **Ambulance** (white square with red cross): Medic recovery point
- **Protest Zone** (red circle): Main area of protester activity

## Simulation Mechanics

### Arrest Process
1. Police perceives violence within `view_dist` (12.5 units)
2. Adds `violence_seen` belief and `pursue_desire`
3. Chases target at 1.5× normal speed
4. May request FIPA backup (5% chance per step)
5. Arrests when within 4 units
6. Protester moved to police HQ, detained for `detention_base_time` cycles

### Journalist Learning Cycle
1. Query all agents for status via FIPA
2. Determine current state (distance, danger, event type)
3. Select action (ε-greedy: explore vs exploit)
4. Execute action and observe outcome
5. Calculate reward based on documentation success/failure
6. Update Q-table using Bellman equation

## Output Monitors

| Monitor | Description |
|---------|-------------|
| Cycle | Current simulation step |
| Aggression | Global aggression percentage |
| Attacks | Total attacks occurred |
| Arrests (BDI) | Total police arrests |
| Documented (RL) | Successfully documented events |
| Journalists Hit | Times journalists were attacked |
| Detained | Currently detained protesters |
| Attacking | Currently attacking protesters |
