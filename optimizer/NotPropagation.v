Require Import Proportional.
Require Import Equivalences.
Require Export OptimizerGates.

Local Close Scope C_scope.
Local Close Scope R_scope.

Local Open Scope ucom_scope.

(* Propagate an X gate on qubit q as far right as possible, cancelling the
   gate if possible. The rules in Nam et al. use Toffoli gates with +/- controls;
   we achieve the same effect by switching between propagating X and propagating
   Z when necessary (although our omission of the Toffoli gate does not allow
   us to change polarity of T/T† gates).

   Note that this optimization may increase the number of gates due to how
   X and Z propagate through CNOT. These additional gates will be removed by
   later passes. *)

Fixpoint propagate_Z {dim} (l : opt_ucom_l dim) q n :=
  match n with
  | O => Z q :: l
  | S n' =>
      match l with
      | [] => [Z q]
      | u :: t =>
          if does_not_reference_appl q u
          then u :: propagate_Z t q n'
          else match u with
               | App1 UO_X n => u :: propagate_Z t q n' (* introduces global phase *)
               | App1 UO_H n => u :: propagate_X t q n' 
               | App1 (UO_Rzπ k) n => u :: propagate_Z t q n'
               | App2 UO_CNOT m n =>
                   if q =? n 
                   then u :: propagate_Z (propagate_Z t n n') m n'
                   else u :: propagate_Z t q n'
               | _ => Z q :: l (* impossible case *)
               end
      end
  end
with propagate_X {dim} (l : opt_ucom_l dim) q n :=
  match n with
  | O => X q :: l
  | S n' =>
      match l with
      | [] => [X q]
      | u :: t =>
          if does_not_reference_appl q u
          then u :: propagate_X t q n'
          else match u with
               | App1 UO_X n => t
               | App1 UO_H n => u :: propagate_Z t q n'
               | App1 (UO_Rzπ k) n =>
                   App1 (UO_Rzπ (2 * DEN - k)%Z) n :: propagate_X t q n'
               | App2 UO_CNOT m n =>
                   if q =? m 
                   then u :: propagate_X (propagate_X t m n') n n'
                   else u :: propagate_X t q n'
               | _ => X q :: l (* impossible case *)
               end
      end
  end.

Fixpoint not_propagation' {dim} (l : opt_ucom_l dim) n :=
  match n with
  | O => l
  | S n' => 
      match l with
      | [] => [] 
      | App1 UO_X q :: t =>
          let l' := propagate_X t q n in
          not_propagation' l' n'
      | u  :: t => u :: not_propagation' t n'
      end
  end.

(* Worst case, every CNOT propagates two X/Z gates, so we start with
   n = 2 × (length n). The n = 0 case should be unreachable. *)
Definition not_propagation {dim} (l : opt_ucom_l dim) := 
  not_propagation' l (2 * List.length l).

(* Proofs *)

Lemma H_X_commutes : forall {dim} q,
  [@H dim q] ++ [X q] =l= [Z q] ++ [H q].
Proof.
  intros. 
  unfold uc_equiv_l, uc_equiv; simpl.
  repeat rewrite Mmult_assoc.
  apply f_equal2; trivial.
  replace (IZR DEN * PI / IZR DEN)%R with PI by (unfold DEN; lra).
  rewrite pauli_x_rotation.
  rewrite pauli_z_rotation.
  rewrite hadamard_rotation.
  autorewrite with eval_db.
  gridify.
  do 2 (apply f_equal2; trivial).
  solve_matrix.
Qed.

Lemma H_Z_commutes : forall {dim} q,
  [@H dim q] ++ [Z q] =l= [X q] ++ [H q].
Proof.
  intros. 
  unfold uc_equiv_l, uc_equiv; simpl.
  repeat rewrite Mmult_assoc.
  apply f_equal2; trivial.
  replace (IZR DEN * PI / IZR DEN)%R with PI by (unfold DEN; lra).
  rewrite pauli_x_rotation.
  rewrite pauli_z_rotation.
  rewrite hadamard_rotation.
  autorewrite with eval_db.
  gridify.
  do 2 (apply f_equal2; trivial).
  solve_matrix.
Qed.

Lemma X_X_cancels : forall {dim} q,
  q < dim -> [@X dim q] ++ [X q] =l= [].
Proof.
  intros. 
  unfold uc_equiv_l, uc_equiv; simpl.
  rewrite pauli_x_rotation.
  autorewrite with eval_db.
  2: lia.
  gridify.
  Qsimpl; reflexivity.
Qed.

Lemma Z_X_commutes : forall {dim} q,
  ([@Z dim q] ++ [X q]) ≅l≅ ([X q] ++ [Z q]).
Proof.
  intros.
  unfold uc_cong_l, uc_cong; simpl.
  replace (IZR DEN * PI / IZR DEN)%R with PI by (unfold DEN; lra).
  rewrite pauli_x_rotation.
  rewrite pauli_z_rotation.
  exists PI.
  repeat rewrite Mmult_assoc.
  rewrite <- Mscale_mult_dist_r.
  apply f_equal2; trivial.
  autorewrite with eval_db.
  gridify.
  rewrite <- Mscale_kron_dist_l.
  rewrite <- Mscale_kron_dist_r.
  do 2 (apply f_equal2; trivial).
  solve_matrix.
  all: rewrite Cexp_PI; lca.
Qed.

Lemma Rz_X_commutes : forall {dim} q k,
  ([@X dim q] ++ [App1 (UO_Rzπ k) q]) ≅l≅ ([App1 (UO_Rzπ (2 * DEN - k)) q] ++ [X q]).
Proof.
  intros.
  Local Opaque Z.sub Z.mul.
  unfold uc_cong_l, uc_cong; simpl.
  exists (IZR k * PI / IZR DEN)%R.
  rewrite pauli_x_rotation.
  repeat rewrite phase_shift_rotation.
  repeat rewrite Mmult_assoc.
  rewrite <- Mscale_mult_dist_r.
  apply f_equal2; trivial.
  autorewrite with eval_db.
  gridify.
  rewrite <- Mscale_kron_dist_l.
  rewrite <- Mscale_kron_dist_r.
  do 2 (apply f_equal2; trivial).
  solve_matrix.
  rewrite minus_IZR.
  autorewrite with R_db.
  repeat rewrite Rmult_plus_distr_r.
  rewrite Cexp_add.
  Local Transparent Z.mul.  
  replace (IZR (2 * DEN) * PI * / IZR DEN)%R with (2 * PI)%R  
    by (unfold DEN; simpl; lra).
  rewrite (Cmult_comm (Cexp (2 * PI))).
  rewrite Cmult_assoc.
  rewrite <- Cexp_add.
  replace (IZR k * PI * / IZR DEN + - IZR k * PI * / IZR DEN)%R with 0%R by lra.
  rewrite Cexp_2PI, Cexp_0.
  lca.
Qed.

Lemma Z_Rz_commutes : forall {dim} q k,
  [@Z dim q] ++ [App1 (UO_Rzπ k) q] =l= [App1 (UO_Rzπ k) q] ++ [Z q].
Proof.
  intros.
  unfold uc_equiv_l, uc_equiv; simpl.
  repeat rewrite Mmult_assoc.
  apply f_equal2; trivial.
  replace (IZR DEN * PI / IZR DEN)%R with PI by (unfold DEN; lra).
  rewrite pauli_z_rotation.
  rewrite phase_shift_rotation.
  autorewrite with eval_db.
  gridify.
  do 2 (apply f_equal2; trivial).
  solve_matrix.
Qed.

Lemma propagate_X_through_CNOT_control : forall {dim} m n,
  [@X dim m] ++ [CNOT m n] =l= [CNOT m n] ++ [X n] ++ [X m].
Proof.
  intros dim m n.
  unfold uc_equiv_l, uc_equiv; simpl.
  repeat rewrite Mmult_assoc.
  apply f_equal2; trivial.
  rewrite pauli_x_rotation.
  autorewrite with eval_db.
  gridify; trivial.
  Qsimpl.
  rewrite Mplus_comm. reflexivity.
  Qsimpl.
  rewrite Mplus_comm. reflexivity.
Qed.

Lemma propagate_X_through_CNOT_target : forall {dim} m n,
  [@X dim n] ++ [CNOT m n] =l= [CNOT m n] ++ [X n].
Proof.
  intros dim m n.
  unfold uc_equiv_l, uc_equiv; simpl.
  repeat rewrite Mmult_assoc.
  apply f_equal2; trivial.
  rewrite pauli_x_rotation.
  autorewrite with eval_db.
  gridify; Qsimpl; reflexivity.
Qed.

Lemma propagate_Z_through_CNOT_control : forall {dim} m n,
  [@Z dim m] ++ [CNOT m n] =l= [CNOT m n] ++ [Z m].
Proof.
  intros dim m n.
  unfold uc_equiv_l, uc_equiv; simpl.
  repeat rewrite Mmult_assoc.
  apply f_equal2; trivial.
  replace (IZR DEN * PI / IZR DEN)%R with PI by (unfold DEN; lra).
  rewrite pauli_z_rotation.
  autorewrite with eval_db.
  gridify; trivial.
  all: replace (∣1⟩⟨1∣ × σz) with (σz × ∣1⟩⟨1∣) by solve_matrix;
       replace (∣0⟩⟨0∣ × σz) with (σz × ∣0⟩⟨0∣) by solve_matrix.
  all: reflexivity.
Qed.

Lemma propagate_Z_through_CNOT_target : forall {dim} m n,
  [@Z dim n] ++ [CNOT m n] =l= [CNOT m n] ++ [Z m] ++ [Z n].
Proof.
  intros dim m n.
  unfold uc_equiv_l, uc_equiv; simpl.
  repeat rewrite Mmult_assoc.
  apply f_equal2; trivial.
  replace (IZR DEN * PI / IZR DEN)%R with PI by (unfold DEN; lra).
  rewrite pauli_z_rotation.
  autorewrite with eval_db.
  gridify; trivial.
  all: replace (σz × ∣1⟩⟨1∣) with ((- 1)%R .* ∣1⟩⟨1∣) by solve_matrix;
       replace (σz × ∣0⟩⟨0∣) with (∣0⟩⟨0∣) by solve_matrix;
       replace (σx × σz) with ((- 1)%R .* (σz × σx)) by solve_matrix.
  all: repeat rewrite Mscale_kron_dist_r;
       repeat rewrite Mscale_kron_dist_l.
  all: reflexivity.
Qed.

Lemma propagate_X_preserves_semantics : forall {dim} (l : opt_ucom_l dim) q n,
  (q < dim)%nat -> propagate_X l q n ≅l≅ (X q :: l) /\ propagate_Z l q n ≅l≅ (Z q :: l).
Proof.
  intros dim l q n Hq.
  generalize dependent q.
  generalize dependent l.
  induction n; intros l q Hq.
  split; reflexivity. 
  destruct l. 
  split; reflexivity.
  (* split the inductive hypothesis into 2 separate hypotheses *)
  assert (IHX : forall (l : opt_ucom_l dim) (q : nat), q < dim -> propagate_X l q n ≅l≅ (X q :: l)).
  { intros. specialize (IHn l0 _ H) as [IHX _]. assumption. }
  assert (IHZ : forall (l : opt_ucom_l dim) (q : nat), q < dim -> propagate_Z l q n ≅l≅ (Z q :: l)).
  { intros. specialize (IHn l0 _ H) as [_ IHZ]. assumption. }
  clear IHn.
  simpl. 
  destruct (does_not_reference_appl q g) eqn:dnr.
  split; [rewrite IHX | rewrite IHZ]; try assumption.
  1,2: rewrite 2 (cons_to_app _ (_ :: l));
       rewrite 2 (cons_to_app _ l);
       repeat rewrite app_assoc.
  1,2: apply uc_equiv_cong_l;
       apply uc_app_congruence; try reflexivity;
       symmetry; 
       apply does_not_reference_commutes_app1; simpl;
       apply andb_true_iff; auto.
  destruct g. 
  - simpl in dnr. apply negb_false_iff in dnr. 
    apply beq_nat_true in dnr. subst.
    dependent destruction o.
    split; [rewrite IHZ | rewrite IHX]; try assumption.
    1,2: rewrite 2 (cons_to_app _ (_ :: l));
         rewrite 2 (cons_to_app _ l);
         repeat rewrite app_assoc.
    1,2: apply uc_equiv_cong_l;
         apply uc_app_congruence; try reflexivity.
    apply H_Z_commutes.
    apply H_X_commutes.
    split; [| rewrite IHZ]; try assumption.
    1,2: repeat rewrite (cons_to_app _ (_ :: l));
         repeat rewrite (cons_to_app _ l);
         repeat rewrite app_assoc.
    apply uc_equiv_cong_l.
    rewrite X_X_cancels; try assumption; reflexivity.
    rewrite Z_X_commutes; reflexivity.
    split; [rewrite IHX | rewrite IHZ]; try assumption.
    1,2: repeat rewrite (cons_to_app _ (_ :: l));
         repeat rewrite (cons_to_app _ l);
         repeat rewrite app_assoc.
    rewrite Rz_X_commutes; reflexivity.
    apply uc_equiv_cong_l.
    rewrite Z_Rz_commutes; reflexivity.
  - dependent destruction o. 
    bdestruct (q =? n0); bdestruct (q =? n1); subst; split.
    1,2: apply uc_equiv_cong_l; unfold uc_equiv_l, uc_equiv; simpl;
         autorewrite with eval_db; bdestruct_all; Msimpl_light; reflexivity.
    all: try rewrite (IHX _ _ Hq); try rewrite (IHZ _ _ Hq).
    all: repeat rewrite (cons_to_app _ (_ :: l));
         repeat rewrite (cons_to_app _ l);
         repeat rewrite app_assoc.
    all: try (apply uc_equiv_cong_l; apply uc_app_congruence; [|reflexivity]).
    2: symmetry; apply propagate_Z_through_CNOT_control.
    2: symmetry; apply propagate_X_through_CNOT_target.
    3, 4: apply does_not_reference_commutes_app2. 
    all: try (apply andb_true_iff; simpl; split; bdestruct_all; reflexivity).
    bdestruct (n1 <? dim).
    2: apply uc_equiv_cong_l; unfold uc_equiv_l, uc_equiv; simpl;
       autorewrite with eval_db; bdestruct_all; Msimpl_light; reflexivity.
    repeat rewrite IHX; try assumption.
    rewrite cons_to_app; rewrite (cons_to_app  _ (_ :: l)); rewrite (cons_to_app _ l).
    repeat rewrite app_assoc.
    apply uc_equiv_cong_l; apply uc_app_congruence; [|reflexivity].
    rewrite <- app_assoc.
    symmetry; apply propagate_X_through_CNOT_control.
    bdestruct (n0 <? dim).
    2: apply uc_equiv_cong_l; unfold uc_equiv_l, uc_equiv; simpl;
       autorewrite with eval_db; bdestruct_all; Msimpl_light; reflexivity.
    repeat rewrite IHZ; try assumption.
    rewrite cons_to_app; rewrite (cons_to_app  _ (_ :: l)); rewrite (cons_to_app _ l).
    repeat rewrite app_assoc.
    apply uc_equiv_cong_l; apply uc_app_congruence; [|reflexivity].
    rewrite <- app_assoc.
    symmetry. apply propagate_Z_through_CNOT_target.
  - inversion o.
Qed.

Lemma propagate_X_well_typed : forall {dim} (l : opt_ucom_l dim) q n,
  (q < dim)%nat -> uc_well_typed_l l -> uc_well_typed_l (propagate_X l q n).
Proof.
  intros dim l q n Hq WT.
  specialize (propagate_X_preserves_semantics l q n Hq) as [H _].
  assert (uc_well_typed_l (X q :: l)).
  constructor; assumption.
  symmetry in H.
  apply uc_cong_l_implies_WT in H; assumption.
Qed.

Lemma not_propagation_sound : forall {dim} (l : opt_ucom_l dim), 
  uc_well_typed_l l -> not_propagation l ≅l≅ l.
Proof.
  intros dim l WT.
  assert (forall n, not_propagation' l n ≅l≅ l).
  { intros n.
    generalize dependent l.
    induction n; intros l WT; try reflexivity.
    Local Opaque propagate_X. 
    destruct l; try reflexivity.
    inversion WT; subst; simpl.
    dependent destruction u.
    all: try (rewrite IHn; try assumption; reflexivity).
    rewrite IHn.
    apply propagate_X_preserves_semantics; try assumption.
    apply propagate_X_well_typed; assumption. }
  apply H.
Qed.

Lemma not_propagation_WT : forall {dim} (l : opt_ucom_l dim),
  uc_well_typed_l l -> uc_well_typed_l (not_propagation l).
Proof.
  intros dim l WT.
  specialize (not_propagation_sound l WT) as H.
  symmetry in H.
  apply uc_cong_l_implies_WT in H; assumption.
Qed.

