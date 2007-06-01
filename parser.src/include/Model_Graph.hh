#ifndef MODEL_GRAPH
#define MODEL_GRAPH
#define DIRECT_COMPUTE
#define SORTED
#define SIMPLIFY
#define SIMPLIFYS
#define SAVE
#define COMPUTE
//#define PRINT_OUT_OUT
//#define PRINT_OUT_1
#define DIRECT_SAVE
#include "ModelTree.hh"
#include "BlockTriangular.hh"

typedef struct t_edge
{
  int index, u_count;
};

typedef struct t_vertex
{
  t_edge *out_degree_edge, *in_degree_edge;
  int nb_out_degree_edges, nb_in_degree_edges;
  int max_nb_out_degree_edges, max_nb_in_degree_edges;
  int index, lag_lead;
};

typedef struct t_model_graph
{
  int nb_vertices;
  t_vertex* vertex;
};

typedef struct t_pList
{
  int* Lag_in, * Lag_out;
  int CurrNb_in, CurrNb_out;
};




void free_model_graph(t_model_graph* model_graph);
void print_Graph(t_model_graph* model_graph);
void Check_Graph(t_model_graph* model_graph);
void copy_model_graph(t_model_graph* model_graph, t_model_graph* saved_model_graph, int nb_endo, int y_kmax);
int ModelBlock_Graph(Model_Block *ModelBlock, int Blck_num,bool dynamic, t_model_graph* model_graph, int nb_endo, int *block_u_count, int *starting_vertex, int* periods, int *nb_table_y, int *mean_var_in_equ);
void IM_to_model_graph(List_IM* First_IM,int Time, int endo, int* y_kmin, int* y_kmax, t_model_graph* model_graph, int* nb_endo, int *stacked_time, double** u1, int* u_count
#ifdef VERIF
                       , Matrix *B, Matrix *D
#endif
                       );
void IM_to_model_graph_new(List_IM* First_IM,int Time, int endo, int* y_kmin, int* y_kmax, t_model_graph* model_graph, int* nb_endo, int *stacked_time, double** u1, int* u_count
#ifdef VERIF
                           , Matrix *B, Matrix *D
#endif
                           );
void IM_to_model_graph_new_new(List_IM* First_IM,int Time, int endo, int* y_kmin, int* y_kmax, t_model_graph* model_graph, int* nb_endo, int *stacked_time, double** u1, int* u_count
#ifdef VERIF
                               , Matrix *B, Matrix *D
#endif
                               );
void reduce_model_graph(t_model_graph* model_graph,int pos);
#endif
