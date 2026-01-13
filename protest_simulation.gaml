model ProtestSimulation

global {
    // agent counts
    int nb_protesters_A <- 15;
    int nb_protesters_B <- 15;
    int nb_police <- 10;
    int nb_medics <- 5;
    int nb_bystanders <- 10;
    int nb_journalists <- 3;
    
    // global variables
    float global_aggression <- 0.5;		// increases by attacks (+0.01), arrests (+0.02), random spikes (+0.05 to +0.15, 40% chance every 30 cycles), major incidents (+0.2, 30% chance every 200 cycles)
    									// decreases by police presence (-0.003 per officer every 20 cycles), detentions (-0.005 per detention every 20 cycles), dynamic decay (base_decay_rate × aggression multiplier, every cycle)
    float base_decay_rate <- 0.001;		// decay rate for global aggression
    int total_arrests <- 0;
    int total_attacks <- 0;
    int total_documented_events <- 0;
    int journalists_hit <- 0;
    
    // rolling averages for charts
    float attack_rate <- 0.0;
    float arrest_rate <- 0.0;
    float doc_rate <- 0.0;
    
    // Q-Learning parameters (for reinforcement learning for journalists)
    float learning_rate <- 0.2;		// 20% weight to new experience, 80% keep old knowledge
    float discount_factor <- 0.95;	// future rewards worth 95% of immediate, value future documentation opportunities highly
    float exploration_rate <- 0.3;	// 30% random exploration initially
    float exploration_decay <- 0.995;	// gradually shifts from exploration to exploitation as learning progresses
    float min_exploration_rate <- 0.05;	// maintain at least 5% randomness to avoid local optima
    
    // locations
    point police_car_location <- {10.0, 10.0};
    point ambulance_location <- {90.0, 90.0};
    point protest_center <- {50.0, 50.0};
    float protest_radius <- 30.0;
    
    // thresholds
    float aggression_attack_threshold <- 0.5;	// protester to attempt an attack
    float police_stress_threshold <- 0.8;	// police add need_rest belief and retreat to base
    float bystander_boredom_threshold <- 0.8;	// bystander leaves simulation
    float medic_exhaustion_threshold <- 0.9;	// medic returns to ambulance to recover
    float detention_base_time <- 20.0;	// # cycles a protester remains detained after arrest
    
    // ==================== BDI PREDICATES ====================
    // string constants for predicate names (avoid typos)
    string violence_location_str <- "violence_location";
    string need_rest_str <- "need_rest";
    
    // mental states for the BDI Police architecture
    // beliefs
    predicate violence_seen <- new_predicate(violence_location_str);
    predicate need_rest_belief <- new_predicate(need_rest_str);
    
    // desires
    predicate patrol_desire <- new_predicate("patrol");
    predicate pursue_desire <- new_predicate("pursue_criminal");
    predicate rest_desire <- new_predicate("rest_at_base");
    
    
    init {
        create IncidentCoordinator number: 1;

        create PoliceCarArea number: 1 {
            location <- police_car_location;
        }
        
        create AmbulanceArea number: 1 {
            location <- ambulance_location;
        }
        
        create ProtestZone number: 1 {
            location <- protest_center;
        }
        
        create Police number: nb_police {
            location <- protest_center + {rnd(-20.0, 20.0), rnd(-20.0, 20.0)};
        }
        
        create ProtesterA number: nb_protesters_A {
            location <- protest_center + {rnd(-protest_radius, protest_radius), rnd(-protest_radius, protest_radius)};
        }
        
        create ProtesterB number: nb_protesters_B {
            location <- protest_center + {rnd(-protest_radius, protest_radius), rnd(-protest_radius, protest_radius)};
        }
        
        create Medic number: nb_medics {
            location <- any_location_in(world.shape);
            home_base <- ambulance_location;
        }
        
        create Journalist number: nb_journalists {
            location <- protest_center + {rnd(-15.0, 15.0), rnd(-15.0, 15.0)};
        }
        
        create Bystander number: nb_bystanders {
            location <- any_location_in(world.shape);
        }
    }
    
    reflex update_global_state {
        float dynamic_decay <- base_decay_rate * (1.0 + global_aggression * 3.0);  // decay is stronger when global aggression is high
        global_aggression <- max(0.25, global_aggression - dynamic_decay);
        exploration_rate <- max(min_exploration_rate, exploration_rate * exploration_decay);	// reduces journalist exploration rate by 0.5% per cycle
        
        // smoothing effects for visualizations
        attack_rate <- attack_rate * 0.98;
        arrest_rate <- arrest_rate * 0.98;
        doc_rate <- doc_rate * 0.98;
    }
    
    // presence of police and high arrest count decreases global crowd aggression
    reflex police_calming when: mod(cycle, 20) = 0 {
        int active_police <- length(Police where each.is_active);
        int detained_count <- length((ProtesterA where each.is_detained) + 
       								(ProtesterB where each.is_detained));
        float deterrent <- (active_police * 0.003) + (detained_count * 0.005);
        global_aggression <- max(0.25, global_aggression - deterrent);
    }
    
    // random aggression spike
    reflex random_tension when: mod(cycle, 30) = 0 and rnd(0.0, 1.0) < 0.4 {
        float increase <- rnd(0.05, 0.15);
        global_aggression <- min(0.9, global_aggression + increase);
        write ">>> Tension rises! +" + int(increase*100) + "%";
    }
    
    reflex spawn_bystanders when: length(Bystander) < 5 and mod(cycle, 50) = 0 {
        create Bystander number: 2 {
            location <- {rnd(80.0, 100.0), rnd(0.0, 100.0)};
        }
    }
}

// ==================== HELPER AGENTS ====================

species IncidentCoordinator skills: [fipa] {
    reflex major_incident when: mod(cycle, 200) = 0 and rnd(0.0, 1.0) < 0.3 {
        global_aggression <- min(0.9, global_aggression + 0.2);

        // 4 protestors from each group get individual 20% aggression boost via FIPA
        list<Protester> targets <- (4 among (ProtesterA where !each.is_detained)) +
                                   (4 among (ProtesterB where !each.is_detained));
        if (!empty(targets)) {
            do start_conversation to: list(targets) protocol: 'fipa-request' performative: 'request'
                contents: ["aggression_boost", 0.2];
        }
        write "!!! MAJOR INCIDENT !!!";
    }
}

// ==================== LOCATIONS ====================

species PoliceCarArea {
    aspect default {
        draw square(8.0) color: #blue border: #darkblue;
        draw "POLICE HQ" at: location + {0, -5} color: #white font: font("Arial", 10, #bold);
    }
}

species AmbulanceArea {
    aspect default {
        draw square(8.0) color: #white border: #red;
        draw "+" at: location color: #red font: font("Arial", 14, #bold);
    }
}

species ProtestZone {
    aspect default {
        draw circle(protest_radius) color: rgb(255, 200, 200, 50) border: #red;
    }
}

// ==================== POLICE ====================
// uses simple_bdi control architecture

species Police skills: [moving, fipa] control: simple_bdi {
    
    float stress_level <- rnd(0.2, 0.5);    // increases during pursuits/arrests
    float patience <- rnd(0.4, 0.9);         // higher patience means slower stress buildup
    
    float view_dist <- 12.5;                 // perception radius
    float my_speed <- 2.0;
    
    bool is_active <- true;
    bool was_hit <- false;
    point target_point <- nil;
    agent current_target <- nil;
    int arrests_made <- 0;
    
    // BDI initialization
    init {
        // initial desire is to simply patrol the area
        do add_desire(patrol_desire);
    }

	// PERCEIVE: detect violent protestors
	perceive target: (
	    (ProtesterA where (each.is_attacking and !each.is_detained)) +
	    (ProtesterB where (each.is_attacking and !each.is_detained))
	) in: view_dist {
	    agent the_criminal <- self;
	    point crime_location <- self.location;

	    focus id: violence_location_str var: location;

	    ask myself {
	        // 'myself' here is the Police agent
	        if (is_active and current_target = nil) {
	            current_target <- the_criminal;
	            target_point <- crime_location;
	            do add_belief(violence_seen);
	            do remove_intention(patrol_desire, false);
	            write name + " sees violence by " + the_criminal.name;
	        }
	    }
	}
    
    // RULES: infer new desires from beliefs
    // if see violence, then desire to pursue (strength 3)
    rule belief: violence_seen new_desire: pursue_desire strength: 3.0;
    
    // if need rest, then desire to rest (strength 5, highest priority)
    rule belief: need_rest_belief new_desire: rest_desire strength: 5.0;
    
    // PLANS: actions to achieve intentions 
    // patrol the protest area (default behavior)
    plan do_patrol intention: patrol_desire {
        if (!is_active) {
            do remove_intention(patrol_desire, false);
            return;
        }
        
        // wander around protest center
        point patrol_point <- protest_center + {rnd(-protest_radius, protest_radius), rnd(-protest_radius, protest_radius)};
        do goto target: patrol_point speed: my_speed;
        
        // slowly increase stress while on duty (patience affects rate)
        stress_level <- min(1.0, stress_level + 0.0005 * (1.0 - patience));
        
        // check if need rest
        if (stress_level > police_stress_threshold) {
        	// only print once
        	if (!has_belief(need_rest_belief)) {
        		do add_belief(need_rest_belief);
            	write name + " stress high (" + int(stress_level*100) + "%) -> needs rest";
        	}
            
        }
    }
    
    // pursue violent protester
    plan do_pursue intention: pursue_desire {
        if (!is_active) {
            do remove_intention(pursue_desire, true);
            do add_desire(patrol_desire);
            return;
        }
        
        // validate target still exists and is attacking
        if (current_target = nil or dead(current_target)) {
            do clear_target;
            return;
        }
        
        Protester p <- Protester(current_target);
        bool still_valid <- p.is_attacking and !p.is_detained;
        target_point <- p.location;
        
        if (!still_valid) {
            do clear_target;
            return;
        }
        
        // chase the target
        do goto target: target_point speed: my_speed * 1.5;
        stress_level <- min(1.0, stress_level + 0.002);
        
        // request FIPA backup
        do request_backup;
        
        // if close enough, arrest directly
        float dist_to_target <- self distance_to current_target;
        if (dist_to_target < 4.0) {
            write name + " close enough (" + int(dist_to_target) + "m) - ARRESTING!";
            do execute_arrest;
        }
    }
    
    // rest at police car
    plan do_rest intention: rest_desire {
        do goto target: police_car_location speed: my_speed;
        
        if (self distance_to police_car_location < 5.0) {
            // recover from stress
            stress_level <- max(0.2, stress_level - 0.03);
            
            if (stress_level < 0.4) {
                do remove_belief(need_rest_belief);
                do remove_intention(rest_desire, true);
                do add_desire(patrol_desire);
                write name + " rested! Stress: " + int(stress_level*100) + "% -> back to patrol";
            }
        }
    }
    
    // direct arrest action (called from pursue plan)
    action execute_arrest {
        if (current_target = nil or dead(current_target)) {
            do clear_target;
            return;
        }
        
        bool arrested <- false;
        
        Protester p <- Protester(current_target);
        if (!p.is_detained) {
            p.is_detained <- true;
            p.is_attacking <- false;
            p.attack_target <- nil;
            p.detention_timer <- detention_base_time;
            p.location <- police_car_location;
            arrested <- true;
            write "*** ARREST: " + name + " arrested " + p.name + " ***";	
        }
        
        if (arrested) {
            total_arrests <- total_arrests + 1;
            arrests_made <- arrests_made + 1;
            arrest_rate <- arrest_rate + 5.0;
            global_aggression <- min(0.9, global_aggression + 0.02);
            stress_level <- min(1.0, stress_level + 0.1);
        }
        
        // clear and go back to patrol
        do clear_target;
    }
    
    action clear_target {
        current_target <- nil;
        target_point <- nil;
        do remove_belief(violence_seen);
        do remove_intention(pursue_desire, true);
        do remove_desire(pursue_desire);

        // always go back to patrol if active and not resting
        if (is_active and !has_belief(need_rest_belief)) {
            do add_desire(patrol_desire);
        }
    }
    
    action request_backup {
        if (rnd(0.0, 1.0) < 0.05) {  // 5% chance per step when pursuing
            list<Police> available <- (Police at_distance(50.0)) where (each.is_active and each != self and each.current_target = nil);
            if (length(available) >= 1) {
                list<Police> helpers <- 2 among available;
                do start_conversation to: list(helpers) protocol: 'fipa-request' performative: 'request'
                    contents: ["backup_needed", target_point];
                point rounded_target <- { round(target_point.x), round(target_point.y) };
                write name + " requesting backup at " + rounded_target;
            }
        }
    }

    reflex handle_fipa_messages when: !empty(requests) {
        loop msg over: requests {
            list msg_content <- list(msg.contents);
            if (string(msg_content[0]) = "backup_needed" and is_active and current_target = nil) {
                point backup_loc <- point(msg_content[1]);
                target_point <- backup_loc;
                do add_belief(violence_seen);
                write name + " responding to backup request";
                do agree message: msg contents: ["on_my_way"];
            } else if (string(msg_content[0]) = "hit") {
                do get_hit;
            } else if (string(msg_content[0]) = "status_query") {
                if (current_target != nil and is_active) {
                    do agree message: msg contents: ["status", "arrest", location];
                } else {
                    do agree message: msg contents: ["status", "idle", nil];
                }
            }
        }
        requests <- [];
    }

    // get hit by protester
    action get_hit {
        was_hit <- true;
        is_active <- false;
        current_target <- nil;
        target_point <- nil;
        
        // reset BDI state - remove specific predicates
        do remove_belief(violence_seen);
        do remove_belief(need_rest_belief);
        do remove_desire(patrol_desire);
        do remove_desire(pursue_desire);
        do remove_desire(rest_desire);
        do remove_intention(patrol_desire, true);
        do remove_intention(pursue_desire, true);
        do remove_intention(rest_desire, true);

        write "!!! POLICE " + name + " DOWN !!!";
    }

    // revive officers who were hit by protestors
    reflex respawn when: mod(cycle, 100) = 0 and !is_active {
        is_active <- true;
        was_hit <- false;
        stress_level <- 0.3;
        location <- police_car_location;
        target_point <- nil;
        current_target <- nil;
        
        // reset BDI state
        // beliefs
        do remove_belief(violence_seen);
        do remove_belief(need_rest_belief);
        
        // desires
        do remove_desire(patrol_desire);
        do remove_desire(pursue_desire);
        do remove_desire(rest_desire);

        // intentions
        do remove_intention(patrol_desire, true);
        do remove_intention(pursue_desire, true);
        do remove_intention(rest_desire, true);

        // add back base patrol desire
        do add_desire(patrol_desire);
        
        write name + " back on duty";
    }
    
    aspect default {
        rgb c <- #blue;
        if (has_desire(pursue_desire)) { c <- #darkblue; }
        if (has_desire(rest_desire)) { c <- #lightblue; }
        if (!is_active) { c <- #gray; }
        
        draw circle(2.0) color: c border: #darkblue;
        draw "P" at: location color: #white font: font("Arial", 10, #bold);
        
        // show perception radius when active
        if (is_active) {
            draw circle(view_dist) color: rgb(0, 0, 255, 20) border: rgb(0, 0, 255, 50);
        }
        
        // Stress bar above agent
        draw rectangle(4, 0.5) at: location + {0, -3} color: #darkgray;
        draw rectangle(4 * stress_level, 0.5) at: location + {-2 + 2*stress_level, -3} color: stress_level > police_stress_threshold ? #red : #green;
    }
}

// ==================== PROTESTER BASE ====================
species Protester skills: [moving, fipa] {
    float aggression <- rnd(0.5, 0.85);
    float courage <- rnd(0.4, 0.8);	// willingness to attack police
    
    bool is_attacking <- false;
    bool is_detained <- false;
    bool is_injured <- false;
    float health <- 1.0;
    float detention_timer <- 0.0;
    agent attack_target <- nil;
    int attack_timer <- 0;
    
    float perception_radius <- 12.0;
    
    
    // abstract method to get rival group (implemented by subclasses)
    list<agent> get_rival_targets {
        return [];
    }
    
    // abstract method to check if target is rival and detained (implemented by subclasses)
    bool is_rival_detained(agent target) {
        return false;
    }
    
    reflex update_detention when: is_detained {
        detention_timer <- detention_timer - 1.0;
    }

    reflex handle_fipa_requests when: !empty(requests) {
        loop msg over: requests {
            list msg_content <- list(msg.contents);
            if (string(msg_content[0]) = "aggression_boost") {
                float boost <- float(msg_content[1]);
                aggression <- min(0.95, aggression + boost);
            } else if (string(msg_content[0]) = "status_query") {
                if (is_attacking and !is_detained) {
                    do agree message: msg contents: ["status", "attack", location];
                } else {
                    do agree message: msg contents: ["status", "idle", nil];
                }
            }
        }
        requests <- [];
    }
    
    // when not attacking, simply wanders around protest center
    reflex wander when: !is_detained and !is_attacking {
        if (self distance_to protest_center > protest_radius + 5) {
            do goto target: protest_center speed: 1.0;
        } else {
            do wander amplitude: 30.0 speed: 0.5;
        }
    }
    
    reflex maybe_attack when: !is_detained and !is_attacking and mod(cycle, 3) = 0 {
        float effective_agg <- (aggression * 0.6) + (global_aggression * 0.4);

        if (effective_agg > aggression_attack_threshold and rnd(0.0, 1.0) < 0.3) {
            float r <- rnd(0.0, 1.0);

            if (r < 0.4) {
                // attack rival group
                list<agent> targets <- get_rival_targets();
                if (!empty(targets)) {
                    attack_target <- one_of(targets);
                    is_attacking <- true;
                    attack_timer <- rnd(15, 40);
                    write name + " attacks rival group!";
                }
            } else if (r < 0.6 and courage > 0.5) {
                // attack police
                list<Police> targets <- Police at_distance(perception_radius) where (each.is_active);
                if (!empty(targets)) {
                    attack_target <- one_of(targets);
                    is_attacking <- true;
                    attack_timer <- rnd(10, 25);
                    write name + " attacks POLICE!";
                }
            } else if (r < 0.8) {
                // attack journalist
                list<Journalist> targets <- Journalist at_distance(perception_radius) where (each.is_active);
                if (!empty(targets)) {
                    attack_target <- one_of(targets);
                    is_attacking <- true;
                    attack_timer <- rnd(8, 20);
                    write name + " attacks JOURNALIST!";
                }
            }
        }
    }
    
    reflex do_attack when: is_attacking and !is_detained {
        attack_timer <- attack_timer - 1;
        
        if (attack_target = nil or dead(attack_target) or attack_timer <= 0) {
            is_attacking <- false;
            attack_target <- nil;
            return;
        }
        
        // if target is a rival protester and is detained, return
        if (is_rival_detained(attack_target)) {
            is_attacking <- false;
            attack_target <- nil;
            return;
        }
        
        do goto target: attack_target speed: 2.0;
        
        if (self distance_to attack_target < 2.0) {
            do hit_target;
        }
    }
    
    action hit_target {
        total_attacks <- total_attacks + 1;
        attack_rate <- attack_rate + 3.0;
        global_aggression <- min(0.9, global_aggression + 0.01);

        if (attack_target is Police) {
            // hit police via FIPA
            if (rnd(0.0, 1.0) < 0.15) {
                do start_conversation to: [attack_target] protocol: 'fipa-request' performative: 'request'
                    contents: ["hit"];
                write "!!! " + name + " HITS POLICE !!!";
            }
        } else if (attack_target is Protester) {
            // hit rival protester
            Protester(attack_target).health <- Protester(attack_target).health - 0.1;
            Protester(attack_target).is_injured <- Protester(attack_target).health < 0.5;
        } else if (attack_target is Journalist) {
            // hit journalist via FIPA
            if (rnd(0.0, 1.0) < 0.4) {
                do start_conversation to: [attack_target] protocol: 'fipa-request' performative: 'request'
                    contents: ["hit"];
                journalists_hit <- journalists_hit + 1;
                write "!!! " + name + " HITS JOURNALIST !!!";
            }
        }
        
        aggression <- max(0.4, aggression - 0.02);
    }

    // each protestor's aggression increases
    reflex increase_frustration when: mod(cycle, 30) = 0 and !is_detained {
        aggression <- min(0.9, aggression + rnd(0.01, 0.03));
    }

    // release prisoners once they've served their time
    reflex release_self when: is_detained and detention_timer <= 0 {
        is_detained <- false;
        detention_timer <- 0.0;
        location <- protest_center + {rnd(-protest_radius, protest_radius),
                                      rnd(-protest_radius, protest_radius)};
        aggression <- rnd(0.4, 0.7);
        write name + " released";
    }
}

// ==================== PROTESTER A ====================

species ProtesterA parent: Protester {
    list<agent> get_rival_targets {
        return ProtesterB at_distance(perception_radius) where (!each.is_detained);
    }
    
    bool is_rival_detained(agent target) {
        return (target is ProtesterB) and ProtesterB(target).is_detained;
    }
    
    aspect default {
        rgb c <- #red;
        if (is_detained) { 
        	c <- #gray;
        }
        else if (is_attacking) { 
        	c <- #darkred;
        }
        else if (is_injured) { 
        	c <- #pink;
        }
        draw triangle(1.5) color: c border: #darkred;
        draw "A" at: location color: #black font: font("Arial", 8, #bold);
    }
}

// ==================== PROTESTER B ====================

species ProtesterB parent: Protester {
    list<agent> get_rival_targets {
        return ProtesterA at_distance(perception_radius) where (!each.is_detained);
    }
    
    bool is_rival_detained(agent target) {
        return (target is ProtesterA) and ProtesterA(target).is_detained;
    }
    
    aspect default {
        rgb c <- #orange;
        if (is_detained) { 
        	c <- #gray;
        }
        else if (is_attacking) { 
        	c <- #darkorange;
        }
        else if (is_injured) { 
        	c <- #lightyellow;
        }
        draw triangle(1.5) color: c border: #darkorange;
        draw "B" at: location color: #black font: font("Arial", 8, #bold);
    }
}



// ==================== MEDIC ====================

species Medic skills: [moving] {
    float exhaustion <- 0.0;
    
    bool is_recovering <- false;
    agent heal_target <- nil;
    point home_base;	// initialized in global species to ambulance location
    int recovery_timer <- 0;
    
    reflex find_injured when: !is_recovering and heal_target = nil {
	    list<Protester> all_injured <- ProtesterA where (each.is_attacking and !each.is_detained) +
	    	ProtesterB where (each.is_attacking and !each.is_detained);
	    
	    if (!empty(all_injured)) {
	        heal_target <- all_injured with_min_of(Protester(each).health);
	    }
	}
    
    reflex heal when: heal_target != nil and !is_recovering {
        if (dead(heal_target)) { 
        	heal_target <- nil; 
        	return;
        }
        
        do goto target: heal_target speed: 1.5;
        
        if (self distance_to heal_target < 2.0) {
        	Protester(heal_target).health <- min(1.0, Protester(heal_target).health + 0.3);
            Protester(heal_target).is_injured <- Protester(heal_target).health < 0.5;
            exhaustion <- exhaustion + 0.15;
            heal_target <- nil;
        }
    }
    
    reflex patrol when: heal_target = nil and !is_recovering {
        do wander amplitude: 45.0 speed: 0.8;
    }
    
    // needs to recover if becomes too exhausted (happens after healing an injured protester)
    reflex check_exhaustion when: exhaustion > medic_exhaustion_threshold and !is_recovering {
        is_recovering <- true;
        recovery_timer <- 40;	// recovers for 40 cycles
    }
    
    reflex recover when: is_recovering {
        do goto target: home_base speed: 2.0;
        if (self distance_to home_base < 3.0) {
            recovery_timer <- recovery_timer - 1;
            exhaustion <- max(0.0, exhaustion - 0.05);
            if (recovery_timer <= 0) { 
            	is_recovering <- false;
            }
        }
    }
    
    aspect default {
        draw circle(2.0) color: is_recovering ? #lightgreen : #green border: #darkgreen;
        draw "+" at: location color: #white font: font("Arial", 12, #bold);
    }
}

// ==================== JOURNALIST ====================
// implements Q-learning reinforcement learning algorithm: wants to maximize reward by getting as close as possible
// when documenting events, while avoiding getting hit by a violent protestor

species Journalist skills: [moving, fipa] {
    float experience <- rnd(0.6, 0.95);	// probability of successfully documenting
    float speed_mult <- rnd(0.9, 1.1);
    
    bool is_documenting <- false;
    int documentation_cooldown <- 0; 
    bool was_hit <- false;
    bool is_active <- true;
    float cumulative_reward <- 0.0;
    int docs <- 0;
    int hits <- 0;
    
    // Q-Learning memory
    map<string, float> q_table;
    string last_state <- "";
    string last_action <- "";
    
    init {
        // initialize Q-table with all state-action pairs
        list<string> dists <- ["vclose", "close", "med", "far"];	// distance to nearest event
        list<string> dangers <- ["safe", "mod", "danger"];		// based on number of nearby attacking protestors
        list<string> events <- ["none", "attack", "arrest"];	// attack = protestor attacking, arrest = police chasing
        list<string> acts <- ["closer", "away", "document", "flee"];	// possible actions journalist can take (closer = get closer, away = move further
        																// document = attempt documentation, flee = emergency escape of scene)
        // utilities initialized to 0 for every possible combination
        loop d over: dists {
            loop dg over: dangers {
                loop e over: events {
                    loop a over: acts {
                        q_table[d + "_" + dg + "_" + e + "_" + a] <- 0.0;
                    }
                }
            }
        }
    }
    
    int count_events {
        return length((ProtesterA where each.is_attacking) + 
       				(ProtesterB where each.is_attacking)) +
               length(Police where (each.current_target != nil));
    }

    list<list> status_responses <- [];
    float closest_event_dist <- 999.0;
    string closest_event_type <- "none";
    point closest_event_loc <- nil;

    // send status queries to all protestors and police (~20% chance per cycle)
    reflex query_status when: is_active and rnd(0.0, 1.0) < 0.2 {
        status_responses <- [];  // clear previous responses
        list<agent> targets <- list(ProtesterA) + list(ProtesterB) + list(Police);
        if (!empty(targets)) {
            do start_conversation to: targets protocol: 'fipa-request' performative: 'request'
                contents: ["status_query"];
        }
    }

    reflex collect_status_responses when: !empty(agrees) {
        loop msg over: agrees {
            list msg_content <- list(msg.contents);
            if (string(msg_content[0]) = "status") {
                status_responses <- status_responses + [msg_content];
            }
        }
        agrees <- [];
    }

    action find_closest_event {
        closest_event_dist <- 999.0;
        closest_event_type <- "none";
        closest_event_loc <- nil;

        loop resp over: status_responses {
            string status_type <- string(resp[1]);
            if (status_type != "idle" and resp[2] != nil) {
                point evt_loc <- point(resp[2]);
                float d <- self distance_to evt_loc;
                if (d < closest_event_dist) {
                    closest_event_dist <- d;
                    closest_event_type <- status_type;
                    closest_event_loc <- evt_loc;
                }
            }
        }
    }

    // returns state string using cached closest event info (call find_closest_event first)
    string get_state {
        // get distance category from closest event
        string ds <- "far";
        if (closest_event_dist < 5) {
            ds <- "vclose";
        } else if (closest_event_dist < 12) {
            ds <- "close";
        } else if (closest_event_dist < 25) {
            ds <- "med";
        }

        // determine danger to journalist based on how many attacking protestors in vicinity
        int nearby <- length((ProtesterA at_distance(8.0) where each.is_attacking) + 
       						(ProtesterB at_distance(8.0) where each.is_attacking));
        string danger <- "safe";
        if (nearby >= 2) {
            danger <- "danger";
        } else if (nearby >= 1) {
            danger <- "mod";
        }

        // return string described state
        return ds + "_" + danger + "_" + closest_event_type;
    }
    
    // get expected reward of state-action pair
    float get_q(string s, string a) {
        string k <- s + "_" + a;
        return q_table contains_key k ? q_table[k] : 0.0;
    }
    
    // choose action that maximizes reward based on current state
    string best_action(string s) {
        list<string> acts <- ["closer", "away", "document", "flee"];
        string best <- "closer";
        float best_v <- get_q(s, "closer");
        loop a over: acts {
            float v <- get_q(s, a);
            if (v > best_v) { 
            	best_v <- v; 
            	best <- a;
            }
        }
        return best;
    }
    
    // get reward value of action that maximizes reward based on current state
    float max_q(string s) {
        list<string> acts <- ["closer", "away", "document", "flee"];
        float m <- -9999.0;
        loop a over: acts {
            float v <- get_q(s, a);
            if (v > m) { 
            	m <- v;
            }
        }
        return m;
    }
    
    // main Q-Learning loop
    reflex q_step when: is_active {
        do find_closest_event;
        string state <- get_state();

        // epsilon-greedy action selection: with probability epsilon, the journalist explores/takes a random action; with probability 1-epsilon,
        // the jorunalist exploits his prior experiences to choose the action with the highest reward for the current state
        string chosen_act;
        if (rnd(0.0, 1.0) < exploration_rate) {
            chosen_act <- one_of(["closer", "away", "document", "flee"]);
        } else {
            chosen_act <- best_action(state);
        }

        bool has_evt <- (closest_event_loc != nil);
        bool did_doc <- false;
        is_documenting <- false;
        
        // decrement cooldown
        if (documentation_cooldown > 0) {
            documentation_cooldown <- documentation_cooldown - 1;
        }
        
        // execute action
        if (chosen_act = "closer") {
            if (has_evt) {
                do goto target: closest_event_loc speed: 2.0 * speed_mult;
            } else {
                do goto target: protest_center speed: 1.0 * speed_mult;
            }
        } else if (chosen_act = "away") {
            if (has_evt) {
                do goto target: location + (location - closest_event_loc) speed: 2.5 * speed_mult;
            } else {
                do wander amplitude: 20.0 speed: 1.0;
            }
        } else if (chosen_act = "document") {
            if (has_evt and documentation_cooldown = 0) {
                float d <- self distance_to closest_event_loc;
                // if they were close enough and deemed to have have enough experience (random number against threshold), document event
                if (d < 20.0 and rnd(0.0, 1.0) < experience) {
                    did_doc <- true;
                    docs <- docs + 1;
                    total_documented_events <- total_documented_events + 1;
                    doc_rate <- doc_rate + 3.0;
                    is_documenting <- true;
                    documentation_cooldown <- 10;  // 10-cycle cooldown
                    write name + " DOCUMENTED at dist " + int(d);
                }
            }
        } else if (chosen_act = "flee") {
            do goto target: {rnd(5.0, 15.0), rnd(5.0, 15.0)} speed: 3.0 * speed_mult;
        }
        
        // calculate reward
        float reward <- 0.0;
        
        bool hit_now <- was_hit;
        if (hit_now) {
        	// big punishment if they were hit, encouraging them not to take previous action again
            reward <- -50.0;
            was_hit <- false;
        }
        
        // various rewards based on how close they documented the event from (closer = better)
        if (did_doc) {
            if (state contains "vclose") { 
            	reward <- reward + 40.0;
            }
            else if (state contains "close") { 
            	reward <- reward + 25.0;
            }
            else if (state contains "med") { 
            	reward <- reward + 12.0;
            }
            else { 
            	reward <- reward + 5.0;
            }
        }
        
        cumulative_reward <- cumulative_reward + reward;
        
        // Q-learning update: Q(s,a) <- Q(s,a) + α[R + γ·max(Q(s',a')) - Q(s,a)]
        if (last_state != "" and last_action != "") {
            string k <- last_state + "_" + last_action;
            float old_q <- q_table contains_key k ? q_table[k] : 0.0;
            float new_q <- old_q + learning_rate * (reward + discount_factor * max_q(state) - old_q);
            q_table[k] <- new_q;
        }
        
        last_state <- state;
        last_action <- chosen_act;
    }
    
    reflex idle_wander when: is_active and count_events() = 0 {
        do wander amplitude: 15.0 speed: 0.6;
    }

    // handle FIPA messages for being hit
    reflex handle_fipa_messages when: !empty(requests) {
        loop msg over: requests {
            list msg_content <- list(msg.contents);
            if (string(msg_content[0]) = "hit") {
                do get_hit;
            }
        }
        requests <- [];
    }

    action get_hit {
        was_hit <- true;
        hits <- hits + 1;
        if (rnd(0.0, 1.0) < 0.35) {
            is_active <- false;
            write "!!! JOURNALIST " + name + " DOWN !!!";
        } else {
            write name + " hit but continues";
        }
    }

    // revive journalists who were hit by protestors
    reflex revive_self when: !is_active and mod(cycle, 120) = 0 {
        is_active <- true;
        was_hit <- false;
        location <- protest_center + {rnd(-10.0, 10.0), rnd(15.0, 25.0)};
        write name + " recovered";
    }
    
    aspect default {
        rgb c <- #purple;
        if (is_documenting) { c <- #magenta; }
        if (!is_active) { c <- #gray; }
        draw square(1.8) color: c border: #darkmagenta;
        draw "J" at: location color: #white font: font("Arial", 10, #bold);
        if (is_documenting) { draw circle(1.0) at: location + {2, -2} color: #yellow; }
        draw string(int(cumulative_reward)) at: location + {0, 3} color: #black font: font("Arial", 8, #plain);
    }
}

// ==================== BYSTANDER ====================

species Bystander skills: [moving] {
    float boredom <- 0.0;
    float fear <- 0.0;
    bool is_leaving <- false;
    
    reflex observe when: !is_leaving {
        int activity <- length(Police at_distance(15.0)) + 
                        length((ProtesterA at_distance(15.0) where each.is_attacking) + 
       							(ProtesterB at_distance(8.0) where each.is_attacking));
        
        if (activity > 0) {
            boredom <- max(0.0, boredom - 0.02 * activity);
            int arrests <- length(Police at_distance(15.0) where (each.current_target != nil));
            if (arrests > 0) { 
            	fear <- min(1.0, fear + 0.1); 
            	boredom <- boredom + 0.03;
            }
        } else {
            boredom <- boredom + 0.008;
        }
        do wander amplitude: 20.0 speed: 0.3;
    }
    
    reflex check_leave when: !is_leaving and (boredom > bystander_boredom_threshold or fear > 0.9) {
        is_leaving <- true;
    }
    
    reflex leave when: is_leaving {
        do goto target: {0.0, rnd(0.0, 100.0)} speed: 1.5;
        if (location.x < 5.0) { do die; }
    }
    
    aspect default {
        draw circle(1.2) color: is_leaving ? #lightgray : #cyan border: #darkcyan;
    }
}

// ==================== EXPERIMENT ====================

experiment ProtestSimulation type: gui {
    parameter "Protesters A" var: nb_protesters_A min: 5 max: 30;
    parameter "Protesters B" var: nb_protesters_B min: 5 max: 30;
    parameter "Police (BDI)" var: nb_police min: 5 max: 20;
    parameter "Journalists (RL)" var: nb_journalists min: 1 max: 10;
    parameter "Initial Aggression" var: global_aggression min: 0.2 max: 0.8;
    parameter "Attack Threshold" var: aggression_attack_threshold min: 0.3 max: 0.7;
    
    output {
        display "Simulation" type: 2d {
            species ProtestZone;
            species PoliceCarArea;
            species AmbulanceArea;
            species Bystander;
            species ProtesterA;
            species ProtesterB;
            species Police;
            species Medic;
            species Journalist;
        }
        
        display "Dynamics" type: 2d refresh: every(5 #cycles) {
            chart "Aggression" type: series size: {1.0, 0.5} position: {0, 0} {
                data "Aggression" value: global_aggression color: #red marker: false;
                data "Attack Threshold" value: aggression_attack_threshold color: #gray marker: false style: line;
            }
            chart "Event Rates (smoothed)" type: series size: {1.0, 0.5} position: {0, 0.5} {
                data "Attacks" value: attack_rate color: #red marker: false;
                data "Arrests" value: arrest_rate color: #blue marker: false;
                data "Documented" value: doc_rate color: #purple marker: false;
            }
        }
        
        display "Journalists (Q-Learning)" type: 2d refresh: every(10 #cycles) {
            chart "Cumulative Rewards" type: series size: {1.0, 0.5} position: {0, 0} {
                loop j over: Journalist {
                    data j.name value: j.cumulative_reward color: rnd_color(200) marker: false;
                }
            }
            chart "Documentation vs Hits" type: series size: {1.0, 0.5} position: {0, 0.5} {
                data "Documented" value: total_documented_events color: #green marker: false;
                data "Hits" value: journalists_hit color: #red marker: false;
            }
        }
        
        display "Police (BDI)" type: 2d refresh: every(10 #cycles) {
            chart "Police Stress Levels" type: series size: {1.0, 0.5} position: {0, 0} {
                loop p over: Police {
                    data p.name value: p.stress_level color: rnd_color(200) marker: false;
                }
            }
            chart "BDI Arrests" type: series size: {1.0, 0.5} position: {0, 0.5} {
                data "Total Arrests" value: total_arrests color: #blue marker: false;
            }
        }
        
        display "Status" type: 2d refresh: every(10 #cycles) {
            chart "Protesters" type: pie size: {0.5, 0.5} position: {0, 0} {
                data "Free A" value: length(ProtesterA where !each.is_detained) color: #red;
                data "Detained A" value: length(ProtesterA where each.is_detained) color: #pink;
                data "Free B" value: length(ProtesterB where !each.is_detained) color: #orange;
                data "Detained B" value: length(ProtesterB where each.is_detained) color: #lightyellow;
            }
            chart "Others" type: pie size: {0.5, 0.5} position: {0.5, 0} {
                data "Active Police" value: length(Police where each.is_active) color: #blue;
                data "Down Police" value: length(Police where !each.is_active) color: #lightblue;
                data "Active Journalists" value: length(Journalist where each.is_active) color: #purple;
                data "Down Journalists" value: length(Journalist where !each.is_active) color: #lavender;
                data "Bystanders" value: length(Bystander) color: #cyan;
            }
            chart "Learning Rate (ε)" type: series size: {1.0, 0.5} position: {0, 0.5} {
                data "Exploration" value: exploration_rate color: #green marker: false;
            }
        }
        
        monitor "Cycle" value: cycle;
        monitor "Aggression" value: int(global_aggression*100);
        monitor "Attacks" value: total_attacks;
        monitor "Arrests (BDI)" value: total_arrests;
        monitor "Documented (RL)" value: total_documented_events;
        monitor "Journalists Hit" value: journalists_hit;
        monitor "Detained" value: length(ProtesterA where each.is_detained) + length(ProtesterB where each.is_detained);
        monitor "Attacking" value: length(ProtesterA where each.is_attacking) + length(ProtesterB where each.is_attacking);
    }
}
