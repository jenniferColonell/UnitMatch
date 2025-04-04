# -*- coding: utf-8 -*-
"""
Basic script to run runUMSet, running UnitMatch on a multi-day set.

Parameters for runUMSet:
    
ks_dirs: List of KS/phy output folders



Estimated drift between recordings is set in drift_est_all; the 3 columns are:
    0 = distance from the shank -- set to zero 
    1 = lateral (x) drift -- set to zero (very difficult to estiamte)
    2 = vertical distance on the shank -- estimate from visual inspection or another tool
There are n_recording-1 entries:
    -first value is the distance (in um) between the 2nd recording and the first
    -second value is the distance between the 3rd recording and the 2nd
    -...and so on

These values are added to the coordinates for the later recording. So if the
2nd recording needs to be shifted 20 um down to match the first, the first 
drift value is -20.

estFP_vs_matchfrac generates false positive rates for the UM-extracted parameter kernels for a range
of matched fractions. This estiamte is used to pick a threshold that (according
to the model) ensures the false postive rate is below fp_max for the match between
each pair of consecutive recordings.


"""
import os

import pandas as pd

import numpy as np


from call_UnitMatch import runUMSet
from UnitMatchPy.assign_unique_id import assign_unique_id
from UnitMatchPy.cross_sess_sum import cross_sess_pairs, remove_transpose, apply_threshold, build_cross_sum
from UnitMatchPy.estimate_fp import estFP_vs_matchfrac, est_matchfrac, thresh_for_FP



def main():
    
    ks_parent = r'Z:\cagatay\MB110_out\results'
    out_parent = r'Z:\cagatay\MB110_out\results\UM_manual_drift'
    
    rec_list = ['200427_MB110_H0_R0_g0',
                '200428_MB110_H0_R0_g0',
                '200501_MB110_H0_R0_g0'
                ]
    
    # Estimates of drift bewteen sessions; coordinates = [distance from shank, x, z]
    drift_est_all = np.zeros((len(rec_list)-1,3))   
    # Replace z-drift estimates with values from manual inspection, Dredge, or other
    # First value is drift between 2nd recording and first, second value is drift from 3rd to 2nd, etc.
    drift_est_all[:,2] = [0,-40]  
    
    # Build input to runUMSet for recordings in rec_list
    # Replace construction of the paths to the KS output and label tsv files
    # for your data and preferred selection criteria
    prb_list = [0]
    label_file_name = 'ibl_call_labels.tsv'
     
    min_thresh = 0.5  # minimum threshold to check FP rate vs. matched fraction
    fp_max = 0.02     # target max false positive rate

     
    for prb_ind in prb_list:
        
        ks_list = list()
        label_list = list()
        result_name = "result"
        for ind1 in range(len(rec_list)):            
            ks_name = f'imec{prb_ind}_ks25_rs1'      # Name for the ks output folder
            ks_list.append(os.path.join(ks_parent,f'{rec_list[ind1]}_imec{prb_ind}',ks_name))
            label_list.append(os.path.join(ks_list[ind1],label_file_name))
            result_name = f'{result_name}_d{ind1}'            
        print(ks_list)
        
        # check for and create directory for output
        dir_name = f'UM_output_rs1_prb{prb_ind}'                 # destination folder
        prb_dir = os.path.join(out_parent,dir_name)
        if not os.path.exists(prb_dir):
            os.mkdir(prb_dir)
        save_dir = os.path.join(prb_dir, f'{result_name}')
        if not os.path.exists(save_dir):
            os.mkdir(save_dir)
        print(f'save dir: {save_dir}') 
        
        runUMSet( ks_list, label_list, save_dir, drift_est_all )
        prob_df = pd.read_csv(os.path.join(save_dir, 'MatchTable.csv'))          
        dup_rem_df = cross_sess_pairs(prob_df)
        tn_rem_df = remove_transpose(dup_rem_df)
    
        roc_df = estFP_vs_matchfrac(save_dir, threshold=None, n_trial=50)
        roc_name = 'est_roc_df.csv'
        roc_df.to_csv(os.path.join(save_dir, roc_name),index=None)

        estfrac_df = est_matchfrac(save_dir, min_thresh)
        adj_thresh_df = thresh_for_FP(roc_df, estfrac_df, fp_max, min_thresh)
        
        adj_th_name = 'adj_th_df.csv'
        adj_thresh_df.to_csv(os.path.join(save_dir,adj_th_name),index=None)
        
        low_thresh_name = 'low_th_df.csv'
        tn_rem_df.to_csv(os.path.join(save_dir,low_thresh_name),index=None)
        
        th_applied_df = apply_threshold(tn_rem_df, adj_thresh_df)
        
        cross_sum_df = build_cross_sum(th_applied_df, 'int')
        cross_sum_df.to_csv(os.path.join(save_dir,'cross_sum_df.csv'),index=None)
    
if __name__ == "__main__":
        main()  